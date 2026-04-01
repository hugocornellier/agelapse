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
          isFullPage: widget.isFullPage,
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
