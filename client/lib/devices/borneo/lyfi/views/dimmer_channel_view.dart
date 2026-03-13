import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

import 'package:borneo_app/devices/borneo/lyfi/view_models/controller_settings_view_model.dart';

class DimmerChannelView extends StatefulWidget {
  final ChannelSettingsDraft initialValue;

  const DimmerChannelView({super.key, required this.initialValue});

  @override
  State<DimmerChannelView> createState() => _DimmerChannelViewState();
}

class _DimmerChannelViewState extends State<DimmerChannelView> {
  late final TextEditingController _nameController;
  late final TextEditingController _wavelengthController;
  late final TextEditingController _wavelength2Controller;
  late String _color;

  String get _name => _nameController.text;

  int? get _wavelength => int.tryParse(_wavelengthController.text);
  int? get _wavelength2 => int.tryParse(_wavelength2Controller.text);

  bool get _nameValid => isValidChannelName(_name);

  bool get _wavelengthValid {
    final wavelength = _wavelength;
    return wavelength != null && isValidChannelWavelength(wavelength);
  }

  bool get _wavelength2Valid {
    final wavelength2 = _wavelength2;
    return wavelength2 != null && isValidChannelWavelength(wavelength2);
  }

  bool get _hasChanges {
    return _name != widget.initialValue.name ||
        _color != widget.initialValue.color ||
        _wavelength != widget.initialValue.wavelength ||
        _wavelength2 != widget.initialValue.wavelength2;
  }

  bool get _canSave => _hasChanges && _nameValid && _wavelengthValid && _wavelength2Valid;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialValue.name);
    _wavelengthController = TextEditingController(text: widget.initialValue.wavelength.toString());
    _wavelength2Controller = TextEditingController(text: widget.initialValue.wavelength2.toString());
    _color = widget.initialValue.color;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _wavelengthController.dispose();
    _wavelength2Controller.dispose();
    super.dispose();
  }

  ChannelSettingsDraft _buildResult() {
    return ChannelSettingsDraft(
      name: _name,
      color: _color,
      wavelength: _wavelength ?? widget.initialValue.wavelength,
      wavelength2: _wavelength2 ?? widget.initialValue.wavelength2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      appBar: AppBar(
        title: Text(context.translate('Channel Settings')),
        actions: [
          TextButton(
            onPressed: _canSave ? () => Navigator.of(context).pop(_buildResult()) : null,
            child: Text(context.translate('Save')),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          primary: true,
          child: Column(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.translate('Name'),
                  hintText: context.translate('1-15 characters'),
                  errorText: _nameValid ? null : context.translate('Invalid name'),
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _wavelengthController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: context.translate('Wavelength'),
                  hintText: '0 - 65535',
                  errorText: _wavelengthValid ? null : context.translate('Invalid wavelength'),
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _wavelength2Controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: context.translate('Wavelength 2'),
                  hintText: '0 - 65535',
                  errorText: _wavelength2Valid ? null : context.translate('Invalid wavelength'),
                ),
                onChanged: (_) => setState(() {}),
              ),
              Text(context.translate('Color')),
              ColorPicker(
                hexInputBar: true,
                enableAlpha: false,
                colorPickerWidth: 200,
                pickerColor: _parseHexColor(context, _color),
                onColorChanged: (color) {
                  setState(() {
                    _color = _colorToHex(color);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseHexColor(BuildContext context, String colorStr) {
    try {
      final normalized = colorStr.startsWith('#') ? colorStr.substring(1) : colorStr;
      if (normalized.length == 6) {
        final value = int.parse(normalized, radix: 16) | 0xFF000000;
        return Color(value);
      }
    } catch (_) {}
    return Theme.of(context).colorScheme.primary;
  }

  String _colorToHex(Color color) {
    // Color.red/green/blue are deprecated; the analyzer suggests a
    // manual conversion expression.  Suppress the warning since the
    // alternative is cumbersome for this small helper.
    // ignore: deprecated_member_use
    final r = color.red.toRadixString(16).padLeft(2, '0');
    // ignore: deprecated_member_use
    final g = color.green.toRadixString(16).padLeft(2, '0');
    // ignore: deprecated_member_use
    final b = color.blue.toRadixString(16).padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }
}
