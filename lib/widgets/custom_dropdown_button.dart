import 'package:flutter/material.dart';
import '../styles/styles.dart';

class CustomDropdownButton<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// Values that should appear disabled (greyed out, not selectable).
  final Set<T>? disabledValues;

  const CustomDropdownButton({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.disabledValues,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: settingsDropdownDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.settingsTextSecondary,
            size: 20,
          ),
          dropdownColor: AppColors.settingsCardBackground,
          borderRadius: BorderRadius.circular(12),
          items: items.map((DropdownMenuItem<T> item) {
            final isDisabled =
                disabledValues != null && disabledValues!.contains(item.value);
            return DropdownMenuItem<T>(
              value: item.value,
              enabled: !isDisabled,
              child: Text(
                item.child is Text ? (item.child as Text).data ?? '' : '',
                style: TextStyle(
                  fontSize: AppTypography.md,
                  color: isDisabled
                      ? AppColors.settingsTextTertiary
                      : AppColors.settingsTextPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
          style: TextStyle(
            fontSize: AppTypography.md,
            color: AppColors.settingsTextPrimary,
          ),
        ),
      ),
    );
  }
}
