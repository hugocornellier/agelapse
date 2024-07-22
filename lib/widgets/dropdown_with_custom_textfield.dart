import 'package:flutter/material.dart';
import '../widgets/setting_list_tile.dart';
import '../services/database_helper.dart';

class DropdownWithCustomTextField extends StatefulWidget {
  final int projectId;
  final String title;
  final int initialValue;
  final ValueChanged<int> onChanged;

  const DropdownWithCustomTextField({
    super.key,
    required this.projectId,
    required this.title,
    required this.initialValue,
    required this.onChanged
  });

  @override
  DropdownWithCustomTextFieldState createState() => DropdownWithCustomTextFieldState();
}

class DropdownWithCustomTextFieldState extends State<DropdownWithCustomTextField> {
  late int currentValue;
  late bool isCustom;
  TextEditingController? _controller;
  final FocusNode _focusNode = FocusNode();
  static const List<int> defaultValues = [1, 5, 10, 16, 24, 30, 60];

  @override
  void initState() {
    super.initState();
    currentValue = widget.initialValue;
    isCustom = !defaultValues.contains(currentValue);
    if (isCustom) {
      print("Here-test1");
      _controller = TextEditingController(text: currentValue.toString());
      print("Here-test2");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleDropdownChanged(int? newValue) {
    if (newValue == null) return;
    if (newValue == -1) {
      _enableCustomMode();
    } else {
      _updateValue(newValue);
    }
  }

  void _handleCustomInputChanged(String value) {
    print("Handling input change");

    final intValue = int.tryParse(value);
    if (intValue != null && intValue >= 1 && intValue <= 120) {
      _updateSetting(intValue);
    }
  }

  void _updateValue(int newValue) {
    _updateSetting(newValue);
    setState(() {
      isCustom = false;
      currentValue = newValue;
      _controller?.dispose();
      _controller = null;
    });
    widget.onChanged(newValue);
  }

  void _enableCustomMode() {
    print("Enabling custom mode...");
    setState(() {
      isCustom = true;
      _controller = TextEditingController(text: "");
      _focusNode.requestFocus();
      print("Done");
    });
  }

  void _updateSetting(int newValue) {
    DB.instance.setSettingByTitle('framerate', newValue.toString(), widget.projectId.toString());
  }

  @override
  Widget build(BuildContext context) {
    return SettingListTile(
      title: widget.title,
      infoContent: "",
      contentWidget: isCustom ? _buildCustomTextField() : _buildDropdown(),
      showInfo: false
    );
  }

  Widget _buildCustomTextField() {
    return SizedBox(
      width: 75,
      child: TextField(
        focusNode: _focusNode,
        controller: _controller,
        decoration: const InputDecoration(
          hintText: '1-120',
          contentPadding: EdgeInsets.all(4.0),
          border: OutlineInputBorder(),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        textInputAction: TextInputAction.done,
        onChanged: _handleCustomInputChanged,
      ),
    );
  }

  Widget _buildDropdown() {
    return DropdownButton<int>(
      value: isCustom ? -1 : currentValue,
      onChanged: _handleDropdownChanged,
      items: defaultValues.map<DropdownMenuItem<int>>((int value) => DropdownMenuItem<int>(
        value: value,
        child: Text(value.toString()),
      )).toList()
        ..add(const DropdownMenuItem<int>(
          value: -1,
          child: Text('Custom'),
        )),
    );
  }
}
