import 'package:flutter/material.dart';
import '../styles/styles.dart';
import 'info_tooltip_icon.dart';

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
                          fontSize: AppTypography.lg,
                          fontWeight: FontWeight.w400,
                          color: isDisabled
                              ? AppColors.settingsTextTertiary
                              : AppColors.settingsTextPrimary,
                        ),
                      ),
                    ),
                    if (showInfo ?? false)
                      InfoTooltipIcon(
                        content: infoContent ?? "No additional information.",
                        disabled: isDisabled,
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
