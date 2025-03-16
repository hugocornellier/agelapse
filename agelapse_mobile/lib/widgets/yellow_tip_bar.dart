import 'package:flutter/material.dart';

import '../styles/styles.dart';

class YellowTipBar extends StatelessWidget {
  final String message;

  const YellowTipBar({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.evenDarkerLightBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lightbulb_outline,
            color: Colors.yellow.withAlpha(204), // Equivalent to opacity 0.8
            size: 30,
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      )
    );
  }
}
