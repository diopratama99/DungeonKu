import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/pixel_colors.dart';

class AssetOrNetworkImage extends StatelessWidget {
  const AssetOrNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
  });

  final String imageUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final isAsset = imageUrl.startsWith('assets/');
    if (isAsset) {
      return Image.asset(
        imageUrl,
        fit: fit,
        errorBuilder: (_, __, ___) => const ColoredBox(color: PixelColors.panelInner),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      placeholder: (_, __) => const ColoredBox(color: PixelColors.panelInner),
      errorWidget: (_, __, ___) => const ColoredBox(color: PixelColors.panelInner),
    );
  }
}
