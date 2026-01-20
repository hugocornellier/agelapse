import 'package:flutter/material.dart';
import '../widgets/in_progress_widget.dart';

class ProgressWidget extends StatelessWidget {
  final bool stabilizingRunningInMain;
  final bool videoCreationActiveInMain;
  final bool importRunningInMain;
  final int progressPercent;
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
    final bool isCalculating = progressPercent <= 0;
    String progressPercentAsStr =
        "${progressPercent > 100 ? 100 : progressPercent}%";

    String minutesRemainingDisplay =
        (minutesRemaining != null && minutesRemaining!.isNotEmpty)
            ? minutesRemaining!
            : "Calculating ETA...";

    String stabilizingMessage = isCalculating
        ? "Stabilizing • Calculating ETA..."
        : "Stabilizing • $progressPercentAsStr • $minutesRemainingDisplay";

    String compilingMessage = isCalculating
        ? "Compiling video • Calculating ETA..."
        : "Compiling video • $progressPercentAsStr • $minutesRemainingDisplay";

    return Column(
      children: [
        if (userRanOutOfSpace && selectedIndex != 3) ...[
          InProgress(
            message: "No storage space on device.",
            goToPage: goToPage,
          ),
        ] else if (importRunningInMain && selectedIndex != 3) ...[
          InProgress(
            message: isCalculating
                ? "Importing..."
                : "Importing... $progressPercentAsStr",
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
