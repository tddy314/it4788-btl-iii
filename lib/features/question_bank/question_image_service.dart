import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors/app_failure.dart';
import '../../core/media/media_upload_service.dart';
import 'question_validation.dart';

/// Chọn/chụp và upload ảnh minh họa câu hỏi. Tách interface để test không
/// phụ thuộc plugin camera/thư viện ảnh.
abstract interface class QuestionImageService {
  /// Trả về đường dẫn tệp đã sao chép vào thư mục của app, hoặc null khi hủy.
  Future<String?> pick({required bool camera, required String userId});

  /// Upload với purpose QUESTION, trả URL server. Không tự retry.
  Future<String> upload(String localPath, {CancelToken? cancelToken});

  /// Xóa tệp nháp cục bộ (bỏ qua lỗi).
  Future<void> discard(String localPath);
}

enum ImageKind { jpeg, png, webp }

/// Nhận diện theo chữ ký tệp, không tin phần mở rộng. GIF bị từ chối vì
/// yêu cầu không làm việc với ảnh động.
ImageKind? detectImageKind(Uint8List bytes) {
  bool starts(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  if (starts(const [0xff, 0xd8, 0xff])) return ImageKind.jpeg;
  if (starts(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return ImageKind.png;
  }
  if (bytes.length > 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return ImageKind.webp;
  }
  return null;
}

/// Kiểm tra kích thước/loại ảnh trước khi đưa vào bản nháp.
void validateImageBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const AppFailure(FailureKind.rejected, 'Tệp ảnh rỗng hoặc bị hỏng.');
  }
  if (bytes.length > QuestionValidation.maxImageBytes) {
    throw const AppFailure(
      FailureKind.rejected,
      'Ảnh vượt quá 4 MB. Hãy chọn ảnh nhỏ hơn.',
    );
  }
  if (detectImageKind(bytes) == null) {
    throw const AppFailure(
      FailureKind.rejected,
      'Chỉ hỗ trợ ảnh tĩnh JPEG, PNG hoặc WebP.',
    );
  }
}

class DeviceQuestionImageService implements QuestionImageService {
  DeviceQuestionImageService(this._upload, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final MediaUploadService _upload;
  final ImagePicker _picker;

  @override
  Future<String?> pick({required bool camera, required String userId}) async {
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 88,
      );
    } on PlatformException catch (error) {
      final denied = error.code.contains('access_denied');
      throw AppFailure(
        FailureKind.rejected,
        denied
            ? (camera
                  ? 'Ứng dụng chưa được cấp quyền camera. Hãy cấp quyền trong Cài đặt của điện thoại.'
                  : 'Ứng dụng chưa được cấp quyền truy cập ảnh. Hãy cấp quyền trong Cài đặt của điện thoại.')
            : 'Không thể mở ${camera ? 'camera' : 'thư viện ảnh'}. Vui lòng thử lại.',
      );
    }
    if (file == null) return null;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      throw const AppFailure(
        FailureKind.rejected,
        'Không đọc được ảnh đã chọn. Hãy chọn ảnh khác.',
      );
    }
    validateImageBytes(bytes);
    await _ensureStillImage(bytes);
    final kind = detectImageKind(bytes)!;
    final String saved;
    try {
      final base = await getApplicationSupportDirectory();
      final folder = Directory(
        '${base.path}/question_bank_drafts/${Uri.encodeComponent(userId)}',
      );
      await folder.create(recursive: true);
      final target = File(
        '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.${kind.name}',
      );
      await target.writeAsBytes(bytes, flush: true);
      saved = target.path;
    } catch (_) {
      throw const AppFailure(
        FailureKind.storage,
        'Không thể lưu ảnh vào bộ nhớ máy. Hãy kiểm tra dung lượng trống.',
      );
    }
    if (camera) {
      // Ảnh chụp tạm của picker không cần nữa sau khi đã sao chép.
      try {
        await File(file.path).delete();
      } catch (_) {}
    }
    return saved;
  }

  Future<void> _ensureStillImage(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      if (codec.frameCount != 1) {
        throw const AppFailure(
          FailureKind.rejected,
          'Không hỗ trợ ảnh động. Hãy chọn ảnh tĩnh.',
        );
      }
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(
        FailureKind.rejected,
        'Ảnh bị hỏng hoặc không đọc được. Hãy chọn ảnh khác.',
      );
    } finally {
      codec?.dispose();
    }
  }

  @override
  Future<String> upload(String localPath, {CancelToken? cancelToken}) async {
    if (!await File(localPath).exists()) {
      throw const AppFailure(
        FailureKind.storage,
        'Ảnh nháp không còn trên máy. Hãy xóa và chọn lại ảnh này.',
      );
    }
    final media = await _upload.upload(
      filePath: localPath,
      purpose: MediaPurpose.question,
      maxBytes: QuestionValidation.maxImageBytes,
      cancelToken: cancelToken,
    );
    return media.url;
  }

  @override
  Future<void> discard(String localPath) async {
    if (!localPath.contains('/question_bank_drafts/')) return;
    try {
      await File(localPath).delete();
    } catch (_) {}
  }
}
