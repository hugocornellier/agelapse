import 'package:flutter/material.dart';

import '../styles/styles.dart';

class YellowTipBar extends StatelessWidget {
  final String message;

  const YellowTipBar({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.settingsCardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.settingsCardBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.settingsAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.info_outline,
              color: AppColors.settingsAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.settingsTextPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
