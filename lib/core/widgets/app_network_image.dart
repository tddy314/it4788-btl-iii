import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Ảnh đã cache có thể xem lại offline; ảnh chưa tải có fallback rõ ràng.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox(
      width: width,
      height: height,
      child: const Center(child: Icon(Icons.image_not_supported_outlined)),
    );
    if (url == null || url!.trim().isEmpty) return placeholder;
    return Semantics(
      label: semanticLabel,
      image: true,
      child: CachedNetworkImage(
        imageUrl: url!,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, _) => SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, this.imageUrl, this.name = '', this.size = 44});
  final String? imageUrl;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: name,
    image: true,
    child: ClipOval(
      child: imageUrl == null || imageUrl!.isEmpty
          ? SizedBox(
              width: size,
              height: size,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.person_outline),
              ),
            )
          : AppNetworkImage(url: imageUrl, width: size, height: size),
    ),
  );
}
