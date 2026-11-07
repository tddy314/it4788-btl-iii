import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/errors/app_failure.dart';
import '../../core/media/media_upload_service.dart';
import '../../core/network/api_client.dart';
import 'post_models.dart';

class DraftAttachment {
  DraftAttachment({
    required this.path,
    required this.type,
    required this.mime,
    required this.size,
    required this.width,
    required this.height,
    this.duration,
    this.uploaded,
    this.uncertain = false,
  });
  final String path, type, mime;
  final int size, width, height;
  final int? duration;
  PostMedia? uploaded;
  bool uncertain;
  Map<String, dynamic> toJson() => {
    'path': path,
    'type': type,
    'mime': mime,
    'size': size,
    'width': width,
    'height': height,
    'duration': duration,
    'uploaded': uploaded?.toJson(),
    'uncertain': uncertain,
  };
  factory DraftAttachment.fromJson(Object? value) {
    final j = object(value);
    return DraftAttachment(
      path: j['path'] as String,
      type: j['type'] as String,
      mime: j['mime'] as String,
      size: j['size'] as int,
      width: j['width'] as int,
      height: j['height'] as int,
      duration: j['duration'] as int?,
      uploaded: j['uploaded'] == null
          ? null
          : PostMedia.fromJson(j['uploaded']),
      uncertain: j['uncertain'] == true,
    );
  }
}

class PostMediaService {
  PostMediaService(this.api);
  final ApiClient api;
  static const imageBytes = 4 * 1024 * 1024, videoBytes = 10 * 1024 * 1024;
  static void validateSizeDuration(
    int size, {
    required bool video,
    Duration? duration,
  }) {
    if (size <= 0 || size > (video ? videoBytes : imageBytes)) {
      throw AppFailure(
        FailureKind.rejected,
        video
            ? 'Video phải có dung lượng từ 1 byte đến 10 MB.'
            : 'Ảnh phải có dung lượng từ 1 byte đến 4 MB.',
      );
    }
    if (video &&
        (duration == null ||
            duration < const Duration(seconds: 1) ||
            duration > const Duration(seconds: 10))) {
      throw const AppFailure(
        FailureKind.rejected,
        'Video phải dài từ 1 đến 10 giây.',
      );
    }
  }

  Future<DraftAttachment> inspect(
    XFile source,
    String userId, {
    bool copy = true,
  }) async {
    final size = await source.length();
    if (size <= 0 || size > videoBytes) {
      throw const AppFailure(
        FailureKind.rejected,
        'Tệp rỗng hoặc vượt quá dung lượng cho phép.',
      );
    }
    final bytes = await source.readAsBytes();
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    final jpeg = starts([0xff, 0xd8, 0xff]);
    final png = starts([137, 80, 78, 71, 13, 10, 26, 10]);
    final webp =
        bytes.length > 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    final video =
        bytes.length > 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp';
    final quickTime =
        video && String.fromCharCodes(bytes.sublist(8, 12)) == 'qt  ';
    if (!jpeg && !png && !webp && !video) {
      throw const AppFailure(
        FailureKind.rejected,
        'Chọn ảnh JPEG/PNG/WebP tĩnh hoặc video MP4/MOV hợp lệ.',
      );
    }
    int width, height;
    Duration? duration;
    if (video) {
      final controller = VideoPlayerController.file(File(source.path));
      try {
        await controller.initialize().timeout(const Duration(seconds: 15));
        duration = controller.value.duration;
        width = controller.value.size.width.round();
        height = controller.value.size.height.round();
        if (width <= 0 || height <= 0) {
          throw const FormatException('Missing video track');
        }
      } catch (_) {
        throw const AppFailure(
          FailureKind.rejected,
          'Không đọc được video. Hãy chọn tệp khác.',
        );
      } finally {
        await controller.dispose();
      }
    } else {
      validateSizeDuration(size, video: false);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          width = descriptor.width;
          height = descriptor.height;
          // A thumbnail is sufficient to verify decodability; retain the real
          // pixel dimensions in the upload metadata.
          final codec = await descriptor.instantiateCodec(
            targetWidth: width >= height ? width.clamp(1, 512) : null,
            targetHeight: height > width ? height.clamp(1, 512) : null,
          );
          try {
            if (codec.frameCount != 1) {
              throw const AppFailure(
                FailureKind.rejected,
                'Không hỗ trợ ảnh động.',
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
    }
    validateSizeDuration(size, video: video, duration: duration);
    final ext = video
        ? (quickTime ? 'mov' : 'mp4')
        : jpeg
        ? 'jpg'
        : png
        ? 'png'
        : 'webp';
    var path = source.path;
    if (copy) {
      final root = await getApplicationSupportDirectory();
      final folder = Directory(
        '${root.path}/post_drafts/${Uri.encodeComponent(userId)}',
      );
      await folder.create(recursive: true);
      path = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await File(source.path).copy(path);
    }
    return DraftAttachment(
      path: path,
      type: video ? 'VIDEO' : 'IMAGE',
      mime: video
          ? (quickTime ? 'video/quicktime' : 'video/mp4')
          : jpeg
          ? 'image/jpeg'
          : 'image/$ext',
      size: size,
      width: width,
      height: height,
      duration: duration?.inSeconds,
    );
  }

  Future<PostMedia> upload(
    DraftAttachment file,
    CancelToken cancel,
    void Function(int, int) progress,
  ) async {
    // Core's upload wrapper does not expose multipart MIME metadata. This
    // feature adapter keeps the shared authenticated client and adds that field.
    return api.request(
      'medias/upload',
      method: 'POST',
      query: {'purpose': 'POST'},
      cancelToken: cancel,
      onSendProgress: progress,
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          contentType: DioMediaType.parse(file.mime),
        ),
      }),
      decode: (v) {
        final j = object(v);
        final uploaded = UploadedMedia.fromJson(v);
        if (uploaded.mediaType != file.type ||
            uploaded.objectKey.isEmpty ||
            uploaded.fileSize <= 0) {
          throw AppFailure.invalidData;
        }
        return PostMedia.fromJson({
          'url': j['url'],
          'key': j['object_key'],
          'type': j['media_type'],
          'size': j['file_size'],
          'width': j['width'] ?? file.width,
          'height': j['height'] ?? file.height,
          'duration': file.duration,
        });
      },
    );
  }

  Future<void> removeLocal(DraftAttachment file, String userId) async {
    final root = await getApplicationSupportDirectory();
    final folder = Directory(
      '${root.path}/post_drafts/${Uri.encodeComponent(userId)}',
    ).absolute.path;
    final target = File(file.path).absolute;
    if (target.parent.path == folder && await target.exists()) {
      await target.delete();
    }
  }
}
