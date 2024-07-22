import 'package:flutter/material.dart';
import '../widgets/setting_list_tile.dart';

class BoolSettingSwitch extends StatefulWidget {
  final String title;
  final bool initialValue;
  final ValueChanged<bool> onChanged;
  final bool? showInfo; // Optional parameter to control info icon visibility
  final String? infoContent; // Optional parameter for info content

  const BoolSettingSwitch({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onChanged,
    this.showInfo,
    this.infoContent,
  });

  @override
  BoolSettingSwitchState createState() => BoolSettingSwitchState();
}

class BoolSettingSwitchState extends State<BoolSettingSwitch> {
  late bool currentValue;

  @override
  void initState() {
    super.initState();
    currentValue = widget.initialValue;
  }

  void _handleChanged(bool newValue) {
    setState(() {
      currentValue = newValue;
    });
    widget.onChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    return SettingListTile(
      showInfo: widget.showInfo,
      infoContent: widget.infoContent,
      title: widget.title,
      contentWidget: Transform.scale(
        scale: 0.8, // Adjust the scale factor to your desired size
        child: Switch(
          value: currentValue,
          onChanged: _handleChanged,
        ),
      ),
    );
  }
}
