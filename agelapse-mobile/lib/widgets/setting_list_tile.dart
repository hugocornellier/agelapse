import 'package:flutter/material.dart';

import '../styles/styles.dart';

class SettingListTile extends StatelessWidget {
  final String title;
  final String? infoContent;
  final Widget contentWidget;
  final bool? showInfo;
  final bool? disabled;

  const SettingListTile({super.key, required this.title, required this.infoContent, required this.contentWidget, required this.showInfo, this.disabled});

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(infoContent ?? "No additional information."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              color: disabled != null && disabled! ? Colors.grey : null,
            ),
          ),
          if (showInfo ?? false)
            IconButton(
              icon: const Icon(Icons.info),
              onPressed: () => _showInfoDialog(context),
              tooltip: 'More Info',
            ),
        ],
      ),
      trailing: contentWidget,
    );
  }
}
