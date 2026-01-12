import 'package:flutter/material.dart';
import '../styles/styles.dart';

class SettingListTile extends StatelessWidget {
  final String title;
  final String? infoContent;
  final Widget contentWidget;
  final bool? showInfo;
  final bool? disabled;
  final bool? showDivider;

  const SettingListTile({
    super.key,
    required this.title,
    required this.infoContent,
    required this.contentWidget,
    required this.showInfo,
    this.disabled,
    this.showDivider,
  });

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.settingsCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            infoContent ?? "No additional information.",
            style: const TextStyle(
              color: AppColors.settingsTextPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "OK",
                style: TextStyle(
                  color: AppColors.settingsAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = disabled ?? false;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: isDisabled
                              ? AppColors.settingsTextTertiary
                              : AppColors.settingsTextPrimary,
                        ),
                      ),
                    ),
                    if (showInfo ?? false)
                      GestureDetector(
                        onTap: () => _showInfoDialog(context),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: isDisabled
                                ? AppColors.settingsTextTertiary
                                : AppColors.settingsTextSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              contentWidget,
            ],
          ),
        ),
        if (showDivider ?? false)
          const Divider(height: 1, color: AppColors.settingsDivider),
      ],
    );
  }
}
