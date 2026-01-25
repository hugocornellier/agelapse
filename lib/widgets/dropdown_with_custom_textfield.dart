import 'package:flutter/material.dart';
import '../styles/styles.dart';
import '../widgets/setting_list_tile.dart';
import '../services/database_helper.dart';

class DropdownWithCustomTextField extends StatefulWidget {
  final int projectId;
  final String title;
  final int initialValue;
  final ValueChanged<int> onChanged;
  final bool? showDivider;
  final bool? showInfo;
  final String? infoContent;

  const DropdownWithCustomTextField({
    super.key,
    required this.projectId,
    required this.title,
    required this.initialValue,
    required this.onChanged,
    this.showDivider,
    this.showInfo,
    this.infoContent,
  });

  @override
  DropdownWithCustomTextFieldState createState() =>
      DropdownWithCustomTextFieldState();
}

class DropdownWithCustomTextFieldState
    extends State<DropdownWithCustomTextField> {
  late int currentValue;
  late int _lastCommittedValue;
  late bool isCustom;
  TextEditingController? _controller;
  final FocusNode _focusNode = FocusNode();
  static const List<int> defaultValues = [1, 5, 10, 16, 24, 30, 60];

  @override
  void initState() {
    super.initState();
    currentValue = widget.initialValue;
    _lastCommittedValue = widget.initialValue;
    isCustom = !defaultValues.contains(currentValue);
    if (isCustom) {
      _controller = TextEditingController(text: currentValue.toString());
    }
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && isCustom) {
      _commitCustomValue();
    }
  }

  void _commitCustomValue() {
    final text = _controller?.text.trim() ?? '';
    final intValue = int.tryParse(text);

    // Validate: must be a number between 1 and 120
    if (intValue == null || intValue < 1 || intValue > 120) {
      // Invalid - revert to last committed value
      _controller?.text = _lastCommittedValue.toString();
      return;
    }

    // Check if value actually changed
    if (intValue == _lastCommittedValue) {
      return;
    }

    // Update state and notify
    setState(() {
      currentValue = intValue;
      _lastCommittedValue = intValue;
    });
    _updateSetting(intValue);
    widget.onChanged(intValue);
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
      _lastCommittedValue = newValue;
      _controller?.dispose();
      _controller = null;
    });
    widget.onChanged(newValue);
  }

  void _enableCustomMode() {
    setState(() {
      isCustom = true;
      _controller = TextEditingController(text: "");
      _focusNode.requestFocus();
    });
  }

  void _updateSetting(int newValue) {
    DB.instance.setSettingByTitle(
      'framerate',
      newValue.toString(),
      widget.projectId.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingListTile(
      title: widget.title,
      infoContent: widget.infoContent,
      contentWidget: isCustom ? _buildCustomTextField() : _buildDropdown(),
      showInfo: widget.showInfo,
      showDivider: widget.showDivider,
    );
  }

  Widget _buildCustomTextField() {
    return Container(
      width: 75,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.settingsCardBorder,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        focusNode: _focusNode,
        controller: _controller,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.settingsTextPrimary,
        ),
        decoration: const InputDecoration(
          hintText: '1-120',
          hintStyle: TextStyle(
            color: AppColors.settingsTextTertiary,
            fontSize: 14,
          ),
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          isDense: true,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        textInputAction: TextInputAction.done,
        onChanged: _handleCustomInputChanged,
        onSubmitted: (_) => _commitCustomValue(),
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.settingsCardBorder,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: isCustom ? -1 : currentValue,
          onChanged: _handleDropdownChanged,
          isDense: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.settingsTextSecondary,
            size: 20,
          ),
          dropdownColor: AppColors.settingsCardBackground,
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.settingsTextPrimary,
          ),
          items: defaultValues
              .map<DropdownMenuItem<int>>(
                (int value) => DropdownMenuItem<int>(
                  value: value,
                  child: Text(value.toString()),
                ),
              )
              .toList()
            ..add(
              const DropdownMenuItem<int>(value: -1, child: Text('Custom')),
            ),
        ),
      ),
    );
  }
}
