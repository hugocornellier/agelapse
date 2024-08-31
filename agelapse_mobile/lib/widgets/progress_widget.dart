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

  const ProgressWidget({
    super.key,
    required this.stabilizingRunningInMain,
    required this.videoCreationActiveInMain,
    required this.importRunningInMain,
    required this.progressPercent,
    required this.goToPage,
    this.selectedIndex = -1,
    this.minutesRemaining,
  });

  @override
  Widget build(BuildContext context) {
    String progressPercentAsStr = "${progressPercent > 100 ? 100 : progressPercent}%";

    String minutesRemainingDisplay = (minutesRemaining != null && minutesRemaining!.isNotEmpty) ? " ($minutesRemaining)" : "";

    return Column(
      children: [
        if (importRunningInMain && selectedIndex != 3) ...[
          InProgress(
            message: "Importing... $progressPercentAsStr",
            goToPage: goToPage,
          ),
        ] else if (stabilizingRunningInMain && selectedIndex != 3) ...[
          InProgress(
            message: "Stabilizing... $progressPercentAsStr",
            goToPage: goToPage,
          ),
        ] else if (videoCreationActiveInMain && selectedIndex != 3) ...[
          InProgress(
            message: "Compiling video... $progressPercentAsStr",
            goToPage: goToPage,
          ),
        ],
      ],
    );
  }
}
