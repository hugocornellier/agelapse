import 'package:flutter/material.dart';
import '../widgets/in_progress_widget.dart';

class ProgressWidget extends StatelessWidget {
  final bool stabilizingRunningInMain;
  final bool videoCreationActiveInMain;
  final bool importRunningInMain;
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
    required this.progressPercent,
    required this.goToPage,
    this.selectedIndex = -1,
    this.minutesRemaining,
    required this.userRanOutOfSpace,
  });

  @override
  Widget build(BuildContext context) {
    final clampedPercent = progressPercent > 100 ? 100.0 : progressPercent;
    final progressPercentAsStr = clampedPercent < 10
        ? "${clampedPercent.toStringAsFixed(1)}%"
        : "${clampedPercent.toStringAsFixed(0)}%";

    final bool hasEta =
        minutesRemaining != null && minutesRemaining!.isNotEmpty;

    // Only show percentage and ETA once ETA is available
    final String stabilizingMessage = hasEta
        ? "Stabilizing • $progressPercentAsStr • $minutesRemaining"
        : "Stabilizing • Estimating ETA...";

    final String compilingMessage = hasEta
        ? "Compiling video • $progressPercentAsStr • $minutesRemaining"
        : "Compiling video • Estimating ETA...";

    return Column(
      children: [
        if (userRanOutOfSpace && selectedIndex != 3) ...[
          InProgress(
            message: "No storage space on device.",
            goToPage: goToPage,
          ),
        ] else if (importRunningInMain && selectedIndex != 3) ...[
          InProgress(
            message: "Importing... $progressPercentAsStr",
            goToPage: goToPage,
          ),
        ] else if (stabilizingRunningInMain && selectedIndex != 3) ...[
          InProgress(
            message: stabilizingMessage,
            goToPage: goToPage,
          ),
        ] else if (videoCreationActiveInMain && selectedIndex != 3) ...[
          InProgress(
            message: compilingMessage,
            goToPage: goToPage,
          ),
        ],
      ],
    );
  }
}
