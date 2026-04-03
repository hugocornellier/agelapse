import 'package:flutter/material.dart';
import '../widgets/in_progress_widget.dart';

class ProgressWidget extends StatelessWidget {
  static const Color _syncPurple = Color(0xFF7C3AED);

  final bool stabilizingRunningInMain;
  final bool videoCreationActiveInMain;
  final bool importRunningInMain;
  final bool isSyncingProjectFolder;
  final double progressPercent;
  final Function(int) goToPage;
  final int selectedIndex;
  final String? minutesRemaining;
  final bool userRanOutOfSpace;

  const ProgressWidget({
    super.key,
    required this.stabilizingRunningInMain,
    required this.videoCreationActiveInMain,
    required this.importRunningInMain,
    this.isSyncingProjectFolder = false,
    required this.progressPercent,
    required this.goToPage,
    this.selectedIndex = -1,
    this.minutesRemaining,
    required this.userRanOutOfSpace,
  });

  @override
  Widget build(BuildContext context) {
    final clampedPercent = progressPercent > 100 ? 100.0 : progressPercent;
    final progressPercentAsStr = "${clampedPercent.toStringAsFixed(1)}%";

    final bool hasEta =
        minutesRemaining != null && minutesRemaining!.isNotEmpty;

    // Only show percentage and ETA once ETA is available
    final String stabilizingMessage = hasEta
        ? "Stabilizing • $progressPercentAsStr • $minutesRemaining"
        : "Stabilizing • Estimating ETA...";

    final String compilingMessage = hasEta
        ? "Compiling video • $progressPercentAsStr • $minutesRemaining"
        : "Preparing video...";

    return Column(
      children: [
        if (userRanOutOfSpace) ...[
          InProgress(
            message: "No storage space on device.",
            goToPage: goToPage,
          ),
        ] else if (isSyncingProjectFolder) ...[
          InProgress(
            message: "Syncing project folder...",
            goToPage: goToPage,
            backgroundColor: _syncPurple,
          ),
        ] else if (importRunningInMain) ...[
          InProgress(
            message: "Importing... $progressPercentAsStr",
            goToPage: goToPage,
          ),
        ] else if (stabilizingRunningInMain) ...[
          InProgress(message: stabilizingMessage, goToPage: goToPage),
        ] else if (videoCreationActiveInMain) ...[
          InProgress(message: compilingMessage, goToPage: goToPage),
        ],
      ],
    );
  }
}
