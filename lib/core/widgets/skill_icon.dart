import 'package:flutter/material.dart';

import 'package:dungeonku/core/theme/pixel_colors.dart';
import 'package:dungeonku/core/widgets/asset_or_network_image.dart';

class SkillIcon extends StatelessWidget {
  const SkillIcon({
    required this.skillId,
    this.size = 40,
    this.borderColor,
    this.disabled = false,
    super.key,
  });

  final String skillId;
  final double size;
  final Color? borderColor;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: PixelColors.inkBackground,
        border: Border.all(
          color: borderColor ?? PixelColors.borderSoft,
          width: 1,
        ),
      ),
      child: AssetOrNetworkImage(
        imageUrl: 'assets/images/skills/$skillId.png',
        fit: BoxFit.cover,
      ),
    );

    if (!disabled) return icon;
    return Opacity(opacity: 0.45, child: icon);
  }
}
