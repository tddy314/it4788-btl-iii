import 'package:dio/dio.dart';

import '../errors/app_failure.dart';
import '../network/api_client.dart';

enum MediaPurpose { avatar, cover, question, post, comment, chat, document }

class UploadedMedia {
  const UploadedMedia({
    required this.url,
    required this.objectKey,
    required this.contentType,
    required this.fileSize,
    required this.mediaType,
  });
  final String url;
  final String objectKey;
  final String contentType;
  final int fileSize;
  final String mediaType;
  factory UploadedMedia.fromJson(Object? value) {
    final json = value as Map<String, dynamic>;
    final url = json['url'] as String;
    if (!Uri.parse(url).hasAuthority) {
      throw const FormatException('Invalid media URL');
    }
    return UploadedMedia(
      url: url,
      objectKey: json['object_key'] as String,
      contentType: json['content_type'] as String,
      fileSize: json['file_size'] as int,
      mediaType: json['media_type'] as String,
    );
  }
}

/// Chỉ upload file, không tạo bài viết/câu hỏi. Không tự gửi lại khi timeout.
class MediaUploadService {
  MediaUploadService(this._api);
  final ApiClient _api;
  Future<UploadedMedia> upload({
    required String filePath,
    required MediaPurpose purpose,
    required int maxBytes,
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = await MultipartFile.fromFile(filePath);
    if (file.length == 0 || file.length > maxBytes) {
      throw const AppFailure(
        FailureKind.rejected,
        'Tệp rỗng hoặc vượt quá dung lượng cho phép.',
      );
    }
    return _api.request(
      'medias/upload',
      method: 'POST',
      query: {'purpose': purpose.name.toUpperCase()},
      data: FormData.fromMap({'file': file}),
      decode: UploadedMedia.fromJson,
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}
