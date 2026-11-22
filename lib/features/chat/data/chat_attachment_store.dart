import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../../../core/errors/app_failure.dart';

class ChatAttachmentStore {
  static Future<String> validateFile(String path) async {
    final file = File(path);
    final size = await file.length();
    if (size == 0 || size > 4 * 1024 * 1024) {
      throw const AppFailure(
        FailureKind.rejected,
        'Ảnh phải có dung lượng lớn hơn 0 và không quá 4 MB.',
      );
    }
    return validateBytes(await file.readAsBytes());
  }

  static Future<String> validateBytes(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
      throw const AppFailure(
        FailureKind.rejected,
        'Ảnh phải có dung lượng lớn hơn 0 và không quá 4 MB.',
      );
    }
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    final png =
        bytes.length >= 8 &&
        List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v);
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    final webp =
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
    if (!png && !jpeg && !webp) {
      throw const AppFailure(
        FailureKind.rejected,
        'Chỉ hỗ trợ ảnh tĩnh JPEG, PNG hoặc WebP.',
      );
    }
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final codec = await descriptor.instantiateCodec(
            targetWidth: descriptor.width.clamp(1, 512),
          );
          try {
            if (codec.frameCount != 1) {
              throw const AppFailure(
                FailureKind.rejected,
                'Không hỗ trợ ảnh động. Hãy chọn ảnh tĩnh.',
              );
            }
            final frame = await codec.getNextFrame();
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(
        FailureKind.rejected,
        'Ảnh bị hỏng hoặc không đọc được. Hãy chọn ảnh khác.',
      );
    }
    return png
        ? 'png'
        : jpeg
        ? 'jpg'
        : 'webp';
  }

  static Future<String> keep(
    String path,
    String userId, {
    Set<String> preserve = const {},
  }) async {
    final file = File(path);
    final extension = await validateFile(path);
    final root = await getApplicationSupportDirectory();
    final folder = Directory(
      '${root.path}/chat-drafts/${Uri.encodeComponent(userId)}',
    );
    await folder.create(recursive: true);
    final files = await folder
        .list(followLinks: false)
        .where((e) => e is File)
        .cast<File>()
        .toList();
    for (final stale in files.where((e) => !preserve.contains(e.path))) {
      await stale.delete();
    }
    if (preserve.length >= 20) {
      throw const AppFailure(
        FailureKind.storage,
        'Hãy xử lý các ảnh đang chờ gửi trước khi chọn thêm.',
      );
    }
    final result = await file.copy(
      '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    return result.path;
  }
}
