import 'package:flutter/material.dart';

class FancyButton {
  static Widget buildElevatedButton(
    BuildContext context, {
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    Color? backgroundColor,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? const Color(0xff212121),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32.0),
          side: BorderSide(color: color, width: 0.5),
        ),
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.black45,
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: Colors.white),
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white),
        ],
      ),
    );
  }
}
