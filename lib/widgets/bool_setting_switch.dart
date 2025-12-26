import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../styles/styles.dart';
import '../widgets/setting_list_tile.dart';

class BoolSettingSwitch extends StatefulWidget {
  final String title;
  final bool initialValue;
  final ValueChanged<bool> onChanged;
  final bool? showInfo;
  final String? infoContent;
  final bool? showDivider;

  const BoolSettingSwitch({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onChanged,
    this.showInfo,
    this.infoContent,
    this.showDivider,
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
      showDivider: widget.showDivider,
      contentWidget: CupertinoSwitch(
        value: currentValue,
        onChanged: _handleChanged,
        activeTrackColor: AppColors.settingsAccent,
        thumbColor: Colors.white,
        inactiveTrackColor: AppColors.settingsCardBorder,
      ),
    );
  }
}
