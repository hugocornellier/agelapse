import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../styles/styles.dart';
import '../utils/platform_utils.dart';
import '../widgets/create_project_sheet.dart';
import '../widgets/desktop_window_controls.dart';

class CreateProjectPage extends StatefulWidget {
  final bool showCloseButton;
  final bool isFullPage;

  const CreateProjectPage({
    super.key,
    this.showCloseButton = true,
    this.isFullPage = false,
  });

  /// Show create project as a modal dialog overlaying the current page.
  static Future<void> showAsDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: AppColors.overlay.withValues(alpha: 0.5),
      builder: (context) => Center(
        child: Container(
          width: 460,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.settingsCardBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.overlay.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: AppColors.background,
              child: const CreateProjectSheet(
                isDefaultProject: false,
                showCloseButton: true,
                isFullPage: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  CreateProjectPageState createState() => CreateProjectPageState();
}

class CreateProjectPageState extends State<CreateProjectPage> {
  @override
  Widget build(BuildContext context) {
    if (!hasCustomTitleBar) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.background, toolbarHeight: 0),
        backgroundColor: AppColors.background,
        body: CreateProjectSheet(
          isDefaultProject: false,
          showCloseButton: widget.showCloseButton,
          isFullPage: true,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          _buildTitleBar(),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: CreateProjectSheet(
                isDefaultProject: false,
                showCloseButton: widget.showCloseButton,
                isFullPage: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 42,
      color: AppColors.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: Platform.isMacOS ? 36 : 0,
              right: Platform.isMacOS ? 0 : 120,
            ),
            child: const DragToMoveArea(child: SizedBox.expand()),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: Platform.isMacOS ? 36 : 12,
              right: 12,
            ),
            child: Row(
              children: [
                const Spacer(),
                if (!Platform.isMacOS) const DesktopWindowControls(),
              ],
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Image.asset(
                'assets/images/agelapselogo.png',
                width: 125,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
