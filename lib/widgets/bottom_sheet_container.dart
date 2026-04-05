import 'package:flutter/material.dart';
import '../styles/styles.dart';

/// A standard bottom sheet container with rounded top corners and surface color.
///
/// Shared across: project_select_sheet, delete_project_dialog,
/// gallery_bottom_sheets.
class BottomSheetContainer extends StatelessWidget {
  final Widget child;

  const BottomSheetContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 20.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
        ),
      ),
      child: child,
    );
  }
}
