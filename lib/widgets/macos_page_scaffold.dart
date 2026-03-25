import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../styles/styles.dart';

/// Placed above a nested Navigator so that [MacosPageScaffold] knows the
/// persistent title bar is already visible and skips its own title bar zone.
class MacosTitleBarScope extends InheritedWidget {
  const MacosTitleBarScope({super.key, required super.child});

  static bool isActive(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MacosTitleBarScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(MacosTitleBarScope oldWidget) => false;
}

/// A scaffold wrapper that handles macOS title bar clearance and provides
/// a secondary navigation bar below the title bar area.
///
/// On macOS: if inside a [MacosTitleBarScope] (nested navigator), renders
/// only the secondary nav bar + body (the persistent title bar is above).
/// Otherwise, renders a title bar zone with centered logo + secondary nav bar.
///
/// On other platforms: renders a standard Material Scaffold with AppBar.
class MacosPageScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final bool showBottomDivider;

  static const double macTitleBarHeight = 42;
  static const double _macCenterLogoWidth = 125;

  const MacosPageScaffold({
    super.key,
    required this.body,
    this.title,
    this.onBack,
    this.onClose,
    this.actions,
    this.backgroundColor,
    this.showBottomDivider = false,
  });

  bool get _hasNavContent =>
      title != null ||
      onBack != null ||
      onClose != null ||
      (actions != null && actions!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return _buildMaterialScaffold(context);
    }
    return _buildMacosScaffold(context);
  }

  Widget _buildMacosScaffold(BuildContext context) {
    final bgColor = backgroundColor ?? AppColors.settingsBackground;
    final hasPersistentTitleBar = MacosTitleBarScope.isActive(context);

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Title bar zone — only needed when NOT inside a nested navigator
          // (i.e. when there's no persistent title bar above us)
          if (!hasPersistentTitleBar)
            SizedBox(
              height: macTitleBarHeight,
              child: Stack(
                children: [
                  DragToMoveArea(child: SizedBox.expand()),
                  IgnorePointer(
                    child: Center(
                      child: Image.asset(
                        'assets/images/agelapselogo.png',
                        width: _macCenterLogoWidth,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Secondary nav bar (if needed)
          if (_hasNavContent) _buildSecondaryNavBar(),
          // Page body
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildSecondaryNavBar() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: showBottomDivider
                ? AppColors.settingsDivider
                : Colors.transparent,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Leading: back arrow or close button
            if (onBack != null)
              _buildNavButton(
                icon: Icons.arrow_back,
                onTap: onBack!,
                color: AppColors.settingsTextPrimary,
              )
            else if (onClose != null)
              _buildNavButton(
                icon: Icons.close,
                onTap: onClose!,
                color: AppColors.textPrimary,
              )
            else
              const SizedBox(width: 40),
            // Title
            if (title != null) ...[
              const SizedBox(width: 8),
              Text(
                title!,
                style: TextStyle(
                  fontSize: AppTypography.xxl,
                  fontWeight: FontWeight.w600,
                  color: onBack != null
                      ? AppColors.settingsTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ],
            const Spacer(),
            // Trailing actions
            if (actions != null) ...actions!,
          ],
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.settingsCardBorder, width: 1),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Scaffold _buildMaterialScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        toolbarHeight: 56,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: backgroundColor,
        automaticallyImplyLeading: onBack != null,
        title: title != null
            ? Text(
                title!,
                style: TextStyle(
                  fontSize: AppTypography.xxl,
                  fontWeight: FontWeight.w600,
                  color: AppColors.settingsTextPrimary,
                ),
              )
            : const Text(""),
        leading: onBack != null
            ? MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onBack,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.settingsCardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.settingsCardBorder,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      color: AppColors.settingsTextPrimary,
                      size: 20,
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          if (onClose != null)
            IconButton(
              icon: Icon(Icons.close, size: 30),
              onPressed: onClose,
            ),
          if (actions != null) ...actions!,
        ],
        bottom: showBottomDivider
            ? PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(
                  height: 1,
                  color: AppColors.settingsDivider,
                ),
              )
            : null,
      ),
      body: body,
    );
  }
}
