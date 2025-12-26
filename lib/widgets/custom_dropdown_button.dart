import 'package:flutter/material.dart';
import '../styles/styles.dart';

class CustomDropdownButton<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  const CustomDropdownButton({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.settingsCardBorder,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.settingsTextSecondary,
            size: 20,
          ),
          dropdownColor: AppColors.settingsCardBackground,
          borderRadius: BorderRadius.circular(12),
          items: items.map((DropdownMenuItem<T> item) {
            return DropdownMenuItem<T>(
              value: item.value,
              child: Text(
                item.child is Text ? (item.child as Text).data ?? '' : '',
                style: const TextStyle(
                  fontSize: 14.0,
                  color: AppColors.settingsTextPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 14.0,
            color: AppColors.settingsTextPrimary,
          ),
        ),
      ),
    );
  }
}
