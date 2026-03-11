import 'package:borneo_app/devices/borneo/lyfi/view_models/controller_settings_view_model.dart';
import 'package:borneo_app/features/devices/views/device_availability_guard.dart';
import 'package:borneo_app/shared/widgets/app_bar_apply_button.dart';
import 'package:borneo_app/shared/widgets/bottom_sheet_picker.dart';
import 'package:flutter_settings_ui/flutter_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

import 'package:provider/provider.dart';

import 'package:borneo_app/devices/borneo/lyfi/views/dimmer_channel_view.dart';

class ControllerSettingsScreen extends StatefulWidget {
  final ControllerSettingsViewModel vm;
  const ControllerSettingsScreen(this.vm, {super.key});

  @override
  State<ControllerSettingsScreen> createState() => _ControllerSettingsScreenState();
}

class _ControllerSettingsScreenState extends State<ControllerSettingsScreen> {
  late Future<void> _initFuture;
  late final TextEditingController _overpowerCutoffController;
  // channel editing is now delegated to a separate screen; controllers are unused

  @override
  void initState() {
    super.initState();
    _overpowerCutoffController = TextEditingController();
    _initFuture = widget.vm.initialize();
  }

  @override
  void dispose() {
    _overpowerCutoffController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.vm,
      builder: (context, child) => DeviceAvailabilityGuard<ControllerSettingsViewModel>(
        viewModel: widget.vm,
        child: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Scaffold(
                appBar: AppBar(title: Text(context.translate("Controller Settings"))),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              if (!widget.vm.isAvailable) {
                return const SizedBox.shrink();
              }
              return Scaffold(
                appBar: AppBar(title: Text(context.translate("Controller Settings"))),
                body: Center(child: Text(context.translate('Initialization failed'))),
              );
            }

            return Consumer<ControllerSettingsViewModel>(
              builder: (context, vm, child) => Scaffold(
                appBar: AppBar(
                  title: Text(context.translate("Controller Settings")),
                  actions: _buildAppBarActions(context),
                  elevation: 1,
                ),
                body: _buildSettingsList(context),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      Selector<ControllerSettingsViewModel, bool>(
        selector: (context, vm) => vm.hasChanges,
        builder: (context, hasChanges, child) => AppBarApplyButton(
          key: const ValueKey('submit'),
          onPressed: context.read<ControllerSettingsViewModel>().canSubmit
              ? () => _showSubmitConfirmationDialog(context)
              : null,
          label: context.translate('Apply'),
        ),
      ),
    ];
  }

  /// Convert the old widget-based groups into a [SettingsList] with sections.
  SettingsList _buildSettingsList(BuildContext context) {
    return SettingsList(
      sections: [
        SettingsSection(
          title: Text(context.translate('LED CONFIGURATION')),
          tiles: [
            if (widget.vm.pwmFreq.available)
              SettingsTile.navigation(
                title: Text(context.translate('PWM frequency')),
                value: Selector<ControllerSettingsViewModel, int?>(
                  selector: (context, vm) => vm.pwmFreq.value,
                  builder: (context, pwmFreq, child) => Text(_formatPwmFreq(pwmFreq)),
                ),
                onPressed: (bc) => _showPwmFreqPicker(bc),
              ),
          ],
        ),

        SettingsSection(
          title: Text(context.translate('LED CHANNELS')),
          tiles: [
            if (widget.vm.channelCountSetting.available)
              SettingsTile.navigation(
                title: Text(context.translate('Enabled channel count')),
                value: Selector<ControllerSettingsViewModel, int?>(
                  selector: (context, vm) => vm.channelCountSetting.value,
                  builder: (context, channelCount, child) => Text('$channelCount'),
                ),
                onPressed: (bc) => _showChannelCountPicker(bc),
              ),

            ...List<SettingsTile>.generate(widget.vm.channels.length, (index) {
              final ch = widget.vm.channels[index];
              return SettingsTile.navigation(
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _parseHexColor(ch.color),
                    border: Border.all(color: Theme.of(context).colorScheme.surfaceDim, width: 1.5),
                  ),
                ),
                title: Text(
                  ch.name,
                  style: ch.nameValid ? null : TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onPressed: (bc) => _editChannel(bc, index),
              );
            }),
          ],
        ),

        // Power & Protection
        if (widget.vm.overpowerEnabled.available ||
            widget.vm.overpowerCutoff.available ||
            widget.vm.overtempEnabled.available ||
            widget.vm.overtempCutoff.available)
          SettingsSection(
            title: Text(context.translate('POWER & PROTECTION')),
            tiles: [
              if (widget.vm.overpowerEnabled.available)
                SettingsTile.switchTile(
                  initialValue: widget.vm.overpowerEnabled.value,
                  onToggle: (bool value) =>
                      context.read<ControllerSettingsViewModel>().overpowerEnabled.setValue(value),
                  title: Text(context.translate("Overpower enabled")),
                ),
              if (widget.vm.overpowerCutoff.available)
                SettingsTile.navigation(
                  title: Text(context.translate('Overpower cut-off')),
                  value: Selector<ControllerSettingsViewModel, int>(
                    selector: (context, vm) => vm.overpowerCutoff.value,
                    builder: (context, cutoff, child) {
                      final cutoffText = cutoff.toString();
                      if (_overpowerCutoffController.text != cutoffText) {
                        _overpowerCutoffController.value = TextEditingValue(
                          text: cutoffText,
                          selection: TextSelection.collapsed(offset: cutoffText.length),
                        );
                      }
                      return SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _overpowerCutoffController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          textAlign: TextAlign.end,
                          decoration: InputDecoration(isDense: true, hintText: '1 - 99999'),
                          onChanged: _onOverpowerCutoffChanged,
                          onSubmitted: _onOverpowerCutoffChanged,
                        ),
                      );
                    },
                  ),
                ),

              if (widget.vm.overtempEnabled.available)
                SettingsTile.switchTile(
                  initialValue: widget.vm.overtempEnabled.value,
                  onToggle: (bool value) => context.read<ControllerSettingsViewModel>().overtempEnabled.setValue(value),
                  title: Text(context.translate("Overtemperature enabled")),
                ),

              if (widget.vm.overtempCutoff.available)
                SettingsTile.navigation(
                  title: Text(context.translate('Overtemperature cut-off')),
                  value: Selector<ControllerSettingsViewModel, int?>(
                    selector: (context, vm) => vm.overtempCutoff.value,
                    builder: (context, cutoff, child) => Text('$cutoff ℃'),
                  ),
                  onPressed: (bc) => _showOvertempCutoffPicker(bc),
                ),
            ],
          ),
      ],
    );
  }

  void _onOverpowerCutoffChanged(String value) {
    if (value.isEmpty) {
      return;
    }

    final parsed = int.tryParse(value);
    if (parsed == null) {
      return;
    }

    final clamped = parsed.clamp(1, 99999);
    if (clamped != parsed) {
      final clampedText = clamped.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _overpowerCutoffController.value = TextEditingValue(
          text: clampedText,
          selection: TextSelection.collapsed(offset: clampedText.length),
        );
      });
    }

    if (widget.vm.overpowerCutoff.value != clamped) {
      widget.vm.overpowerCutoff.setValue(clamped);
    }
  }

  void _showSubmitConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog.adaptive(
          title: Text(context.translate('Confirm Submit')),
          content: Text(
            context.translate(
              'Please carefully check the configuration. Incorrect configuration may cause hardware damage or other dangerous situations. Submitting will reboot the device.\nDo you want to proceed?',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(context.translate('Cancel'))),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await widget.vm.submit();
                if (context.mounted) {
                  await Navigator.of(context).maybePop();
                }
              },
              child: Text(context.translate('Confirm')),
            ),
          ],
        );
      },
    );
  }

  Color _parseHexColor(String colorStr) {
    try {
      final normalized = colorStr.startsWith('#') ? colorStr.substring(1) : colorStr;
      if (normalized.length == 6) {
        final value = int.parse(normalized, radix: 16) | 0xFF000000;
        return Color(value);
      }
    } catch (_) {}
    return Theme.of(context).colorScheme.primary;
  }

  Future<void> _editChannel(BuildContext context, int index) async {
    final draft = await Navigator.push<ChannelSettingsDraft>(
      context,
      MaterialPageRoute(builder: (ctx) => DimmerChannelView(initialValue: widget.vm.getChannelDraft(index))),
    );

    if (draft != null && context.mounted) {
      widget.vm.applyChannelDraft(index, draft);
    }
  }

  void _showChannelCountPicker(BuildContext context) {
    final maxChannels = widget.vm.lyfiDeviceInfo.channelCountMax;
    final currentValue = widget.vm.channelCountSetting.value;

    BottomSheetPicker.show(
      context: context,
      title: context.translate('Select channel count'),
      items: List.generate(maxChannels, (index) => '${index + 1}'),
      selectedIndex: currentValue - 1,
      onItemSelected: (index) {
        widget.vm.channelCountSetting.setValue(index + 1);
      },
    );
  }

  String _formatPwmFreq(int? freq) {
    if (freq == null) return '';
    if (freq >= 1000) {
      return '${(freq / 1000).round()} kHz';
    } else {
      return '$freq Hz';
    }
  }

  void _showPwmFreqPicker(BuildContext context) {
    final currentValue = widget.vm.pwmFreq.value;
    final options = [
      {'value': 500, 'label': '500 Hz'},
      {'value': 1000, 'label': '1 kHz'},
      {'value': 2000, 'label': '2 kHz'},
      {'value': 3000, 'label': '3 kHz'},
      {'value': 4000, 'label': '4 kHz'},
      {'value': 8000, 'label': '8 kHz'},
      {'value': 19000, 'label': '19 kHz'},
      {'value': 19530, 'label': '19.53 kHz'},
    ];

    final currentIndex = options.indexWhere((option) => option['value'] == currentValue);

    BottomSheetPicker.show(
      context: context,
      title: context.translate('Select PWM frequency'),
      items: options.map((option) => option['label'] as String).toList(),
      selectedIndex: currentIndex >= 0 ? currentIndex : 0,
      onItemSelected: (index) {
        final selectedOption = options[index];
        widget.vm.pwmFreq.setValue(selectedOption['value'] as int);
      },
    );
  }

  void _showOvertempCutoffPicker(BuildContext context) {
    final currentValue = widget.vm.overtempCutoff.value;
    final options = [
      {'value': 55, 'label': '55 ℃'},
      {'value': 60, 'label': '60 ℃'},
      {'value': 65, 'label': '65 ℃'},
      {'value': 70, 'label': '70 ℃'},
      {'value': 75, 'label': '75 ℃'},
    ];

    final currentIndex = options.indexWhere((option) => option['value'] == currentValue);

    BottomSheetPicker.show(
      context: context,
      title: context.translate('Select overtemperature cut-off'),
      items: options.map((option) => option['label'] as String).toList(),
      selectedIndex: currentIndex >= 0 ? currentIndex : 0,
      onItemSelected: (index) {
        final selectedOption = options[index];
        widget.vm.overtempCutoff.setValue(selectedOption['value'] as int);
      },
    );
  }
}
