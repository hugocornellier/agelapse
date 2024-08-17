import 'package:flutter/material.dart';

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
    return DropdownButton<T>(
      value: value,
      items: items.map((DropdownMenuItem<T> item) {
        return DropdownMenuItem<T>(
          value: item.value,
          child: Text(
            item.child is Text ? (item.child as Text).data ?? '' : '',
            style: const TextStyle(fontSize: 14.0),
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}
