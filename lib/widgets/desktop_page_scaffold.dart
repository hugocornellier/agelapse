import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../styles/styles.dart';
import '../utils/platform_utils.dart';
import 'desktop_window_controls.dart';

/// Placed above a nested Navigator so that [DesktopPageScaffold] knows the
/// persistent title bar is already visible and skips its own title bar zone.
class DesktopTitleBarScope extends InheritedWidget {
  const DesktopTitleBarScope({super.key, required super.child});

  static bool isActive(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DesktopTitleBarScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(DesktopTitleBarScope oldWidget) => false;
}

/// A scaffold wrapper that handles desktop title bar clearance and provides
/// a secondary navigation bar below the title bar area.
///
/// On macOS: if inside a [DesktopTitleBarScope] (nested navigator), renders
/// only the secondary nav bar + body (the persistent title bar is above).
/// Otherwise, renders a title bar zone with centered logo + secondary nav bar.
///
/// On other platforms: renders a standard Material Scaffold with AppBar.
class DesktopPageScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final bool showBottomDivider;

  static const double titleBarHeight = 42;
  static const double _centerLogoWidth = 125;

  const DesktopPageScaffold({
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
    if (!hasCustomTitleBar) {
      return _buildMaterialScaffold(context);
    }
    return _buildMacosScaffold(context);
  }

  Widget _buildMacosScaffold(BuildContext context) {
    final bgColor = backgroundColor ?? AppColors.settingsBackground;
    final hasPersistentTitleBar = DesktopTitleBarScope.isActive(context);

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Title bar zone — only needed when NOT inside a nested navigator
          // (i.e. when there's no persistent title bar above us)
          if (!hasPersistentTitleBar)
            Container(
              height: titleBarHeight,
              color: AppColors.surface,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      right: (Platform.isLinux || Platform.isWindows) ? 120 : 0,
                    ),
                    child: DragToMoveArea(child: SizedBox.expand()),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Image.asset(
                        'assets/images/agelapselogo.png',
                        width: _centerLogoWidth,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (Platform.isLinux || Platform.isWindows)
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(child: DesktopWindowControls()),
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

  static const double navBarHeight = 52;
  static const double navButtonSize = 32;
  static const double navIconSize = 16;
  static const double navButtonRadius = 10;

  Widget _buildSecondaryNavBar() {
    return Container(
      height: navBarHeight,
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
              SizedBox(width: navButtonSize),
            // Title
            if (title != null) ...[
              const SizedBox(width: 8),
              Text(
                title!,
                style: TextStyle(
                  fontSize: AppTypography.lg,
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
          width: navButtonSize,
          height: navButtonSize,
          decoration: BoxDecoration(
            color: AppColors.settingsCardBackground,
            borderRadius: BorderRadius.circular(navButtonRadius),
            border: Border.all(color: AppColors.settingsCardBorder, width: 1),
          ),
          child: Icon(icon, color: color, size: navIconSize),
        ),
      ),
    );
  }

  Scaffold _buildMaterialScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        toolbarHeight: navBarHeight,
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
                  fontSize: AppTypography.lg,
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
                      borderRadius: BorderRadius.circular(navButtonRadius),
                      border: Border.all(
                        color: AppColors.settingsCardBorder,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      color: AppColors.settingsTextPrimary,
                      size: navIconSize,
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          if (onClose != null)
            IconButton(
              icon: Icon(Icons.close, size: navIconSize),
              onPressed: onClose,
            ),
          if (actions != null) ...actions!,
        ],
        bottom: showBottomDivider
            ? PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: AppColors.settingsDivider),
              )
            : null,
      ),
      body: body,
    );
  }
}
