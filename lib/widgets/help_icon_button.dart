import 'package:flutter/material.dart';
import '../widgets/desktop_page_scaffold.dart';
import '../styles/styles.dart';

class HelpIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const HelpIconButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const size = DesktopPageScaffold.navButtonSize;
    const iconSize = DesktopPageScaffold.navIconSize;
    const radius = DesktopPageScaffold.navButtonRadius;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.settingsCardBorder, width: 1),
          ),
          child: Icon(
            Icons.help_outline_rounded,
            color: AppColors.settingsTextSecondary,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}
