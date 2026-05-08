import 'dart:convert';
import 'dart:typed_data';

import 'package:borneo_app/devices/borneo/lyfi/view_models/base_lyfi_device_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/api.dart';

bool isValidChannelName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }

  try {
    final bytes = utf8.encode(value);
    return bytes.isNotEmpty && bytes.length <= 15;
  } catch (_) {
    return false;
  }
}

bool isValidChannelWavelength(int value) => value >= 0 && value <= 0xFFFF;

class ChannelSettingsDraft {
  final String name;
  final String color;
  final int wavelength;
  final int wavelength2;
  final double fraction;
  final double ratio;

  const ChannelSettingsDraft({
    required this.name,
    required this.color,
    required this.wavelength,
    required this.wavelength2,
    required this.fraction,
    required this.ratio,
  });

  bool get nameValid => isValidChannelName(name);
  bool get wavelengthValid => isValidChannelWavelength(wavelength);
  bool get wavelength2Valid => isValidChannelWavelength(wavelength2);
}

class NvsSettingEntry<T> {
  final String namespace;
  final String key;
  T _value;
  T _initialValue;
  final void Function() _notifyListeners;
  bool available;

  T get value => _value;
  bool get changed => available && _value != _initialValue;
  void setValue(T value) {
    _value = value;
    _notifyListeners();
  }

  void reset() {
    _value = _initialValue;
    _notifyListeners();
  }

  NvsSettingEntry(
    T initialValue,
    this._notifyListeners, {
    required this.namespace,
    required this.key,
    this.available = true,
  }) : _value = initialValue,
       _initialValue = initialValue;
}

class ChannelSettingsEntry {
  final int index;
  final void Function() _notifyListeners;

  String _name;
  String _initialName;
  String _color;
  String _initialColor;
  int _initialWavelength;
  int _wavelength;
  int _initialWavelength2;
  int _wavelength2;
  double _fraction;
  double _initialFraction;
  double _ratio;
  double _initialRatio;

  String get name => _name;
  String get color => _color;
  int get wavelength => _wavelength;
  int get wavelength2 => _wavelength2;
  double get fraction => _fraction;
  double get ratio => _ratio;

  bool get nameChanged => _name != _initialName;
  bool get colorChanged => _color != _initialColor;
  bool get wavelengthChanged => _wavelength != _initialWavelength;
  bool get wavelength2Changed => _wavelength2 != _initialWavelength2;
  bool get fractionChanged => _fraction != _initialFraction;
  bool get ratioChanged => _ratio != _initialRatio;

  bool get changed =>
      nameChanged || colorChanged || wavelengthChanged || wavelength2Changed || fractionChanged || ratioChanged;

  bool get nameValid => isValidChannelName(_name);
  bool get wavelengthValid => isValidChannelWavelength(_wavelength);
  bool get wavelength2Valid => isValidChannelWavelength(_wavelength2);

  ChannelSettingsEntry({
    required this.index,
    required String name,
    required String color,
    required int wavelength,
    required int wavelength2,
    required double fraction,
    required double ratio,
    required void Function() notifyListeners,
  }) : _name = name,
       _initialName = name,
       _color = color,
       _initialColor = color,
       _wavelength = wavelength,
       _initialWavelength = wavelength,
       _wavelength2 = wavelength2,
       _initialWavelength2 = wavelength2,
       _fraction = fraction,
       _initialFraction = fraction,
       _ratio = ratio,
       _initialRatio = ratio,
       _notifyListeners = notifyListeners;

  void setName(String value) {
    if (_name != value) {
      _name = value;
      _notifyListeners();
    }
  }

  void setColor(String value) {
    if (_color != value) {
      _color = value;
      _notifyListeners();
    }
  }

  void setWavelength(int value) {
    if (_wavelength != value) {
      _wavelength = value;
      _notifyListeners();
    }
  }

  void setWavelength2(int value) {
    if (_wavelength2 != value) {
      _wavelength2 = value;
      _notifyListeners();
    }
  }

  void setFraction(double value) {
    if (_fraction != value) {
      _fraction = value;
      _notifyListeners();
    }
  }

  void setRatio(double value) {
    if (_ratio != value) {
      _ratio = value;
      _notifyListeners();
    }
  }

  ChannelSettingsDraft toDraft() {
    return ChannelSettingsDraft(
      name: _name,
      color: _color,
      wavelength: _wavelength,
      wavelength2: _wavelength2,
      fraction: _fraction,
      ratio: _ratio,
    );
  }

  void applyDraft(ChannelSettingsDraft draft) {
    if (_name == draft.name &&
        _color == draft.color &&
        _wavelength == draft.wavelength &&
        _wavelength2 == draft.wavelength2 &&
        _fraction == draft.fraction &&
        _ratio == draft.ratio) {
      return;
    }

    _name = draft.name;
    _color = draft.color;
    _wavelength = draft.wavelength;
    _wavelength2 = draft.wavelength2;
    _fraction = draft.fraction;
    _ratio = draft.ratio;
    _notifyListeners();
  }

  void syncInitial() {
    _initialName = _name;
    _initialColor = _color;
    _initialWavelength = _wavelength;
    _initialWavelength2 = _wavelength2;
    _initialFraction = _fraction;
    _initialRatio = _ratio;
  }
}

class ControllerSettingsViewModel extends BaseLyfiDeviceViewModel {
  late final int maxChannelCount;
  late final NvsSettingEntry<int> nominalPfdSetting;
  late final NvsSettingEntry<int> nominalPowerSetting;
  late final NvsSettingEntry<int> pwmFreq;
  late final NvsSettingEntry<bool> overpowerEnabled;
  late final NvsSettingEntry<int> overpowerCutoff;
  late final NvsSettingEntry<bool> overtempEnabled;
  late final NvsSettingEntry<int> overtempCutoff;
  late final NvsSettingEntry<int> channelCountSetting;

  bool _outputInvertEnabled = false;
  bool _initialOutputInvertEnabled = false;
  bool _outputInvertEnabledAvailable = false;

  bool get outputInvertEnabled => _outputInvertEnabled;
  bool get outputInvertEnabledAvailable => _outputInvertEnabledAvailable;
  bool get outputInvertEnabledChanged =>
      _outputInvertEnabledAvailable && _outputInvertEnabled != _initialOutputInvertEnabled;

  void setOutputInvertEnabled(bool value) {
    if (_outputInvertEnabled != value) {
      _outputInvertEnabled = value;
      notifyListeners();
    }
  }

  List<ChannelSettingsEntry> _channels = const [];
  List<ChannelSettingsEntry> get channels => _channels;

  bool get hasChanges {
    final basicChanged =
        nominalPfdSetting.changed ||
        nominalPowerSetting.changed ||
        pwmFreq.changed ||
        overpowerEnabled.changed ||
        overpowerCutoff.changed ||
        overtempEnabled.changed ||
        overtempCutoff.changed ||
        channelCountSetting.changed ||
        outputInvertEnabledChanged;
    final channelChanged = _channels.any((channel) => channel.changed);
    return basicChanged || channelChanged;
  }

  bool get canSubmit =>
      hasChanges &&
      _channels.every((channel) => channel.nameValid && channel.wavelengthValid && channel.wavelength2Valid);

  ChannelSettingsDraft getChannelDraft(int index) => _channels[index].toDraft();

  void applyChannelDraft(int index, ChannelSettingsDraft draft) {
    _channels[index].applyDraft(draft);
  }

  ControllerSettingsViewModel({
    required super.deviceManager,
    required super.globalEventBus,
    required super.notification,
    required super.gt,
    required super.wotThing,
  });

  @override
  Future<void> onInitialize() async {
    await super.onInitialize();

    nominalPfdSetting = NvsSettingEntry<int>(0, notifyListeners, namespace: "led", key: "npfd");
    nominalPowerSetting = NvsSettingEntry<int>(0, notifyListeners, namespace: "led", key: "npower");
    pwmFreq = NvsSettingEntry<int>(500, notifyListeners, namespace: "led", key: "pwmfreq");
    overpowerEnabled = NvsSettingEntry<bool>(true, notifyListeners, namespace: "protect", key: "opp.en");
    overpowerCutoff = NvsSettingEntry<int>(999999, notifyListeners, namespace: "protect", key: "opp.v");
    overtempEnabled = NvsSettingEntry<bool>(true, notifyListeners, namespace: "protect", key: "ot.en");
    overtempCutoff = NvsSettingEntry<int>(65, notifyListeners, namespace: "protect", key: "ot.v");

    // Initialize channel count setting from device info. Channel metadata is loaded from NVS.
    final info = super.lyfiDeviceInfo;
    channelCountSetting = NvsSettingEntry<int>(info.channelCount, notifyListeners, namespace: "led", key: "chcount");

    maxChannelCount = info.channelCountMax;

    try {
      await _initSetting(
        nominalPfdSetting,
        () async => await this.borneoDeviceApi.getFactoryNvsU16(
          boundDevice!.device,
          nominalPfdSetting.namespace,
          nominalPfdSetting.key,
        ),
      );
      await _initSetting(
        nominalPowerSetting,
        () async => await this.borneoDeviceApi.getFactoryNvsU16(
          boundDevice!.device,
          nominalPowerSetting.namespace,
          nominalPowerSetting.key,
        ),
      );
      await _initSetting(
        pwmFreq,
        () async => await this.borneoDeviceApi.getFactoryNvsU16(boundDevice!.device, pwmFreq.namespace, pwmFreq.key),
      );
      await _initSetting(
        overpowerEnabled,
        () async =>
            (await this.borneoDeviceApi.getFactoryNvsU8(
              boundDevice!.device,
              overpowerEnabled.namespace,
              overpowerEnabled.key,
            )) !=
            0,
      );
      await _initSetting(
        overpowerCutoff,
        () async => await this.borneoDeviceApi.getFactoryNvsI32(
          boundDevice!.device,
          overpowerCutoff.namespace,
          overpowerCutoff.key,
        ),
      );
      await _initSetting(
        overtempEnabled,
        () async =>
            (await this.borneoDeviceApi.getFactoryNvsU8(
              boundDevice!.device,
              overtempEnabled.namespace,
              overtempEnabled.key,
            )) !=
            0,
      );
      await _initSetting(
        overtempCutoff,
        () async => await this.borneoDeviceApi.getFactoryNvsU8(
          boundDevice!.device,
          overtempCutoff.namespace,
          overtempCutoff.key,
        ),
      );
      await _initSetting(
        channelCountSetting,
        () async => await this.borneoDeviceApi.getFactoryNvsU8(
          boundDevice!.device,
          channelCountSetting.namespace,
          channelCountSetting.key,
        ),
      );

      final supportedResourcePaths = await lyfiDeviceApi.getSupportedResourcePaths(
        boundDevice!.device,
        cancelToken: masterCancellation,
      );
      _outputInvertEnabledAvailable = supportedResourcePaths.contains(LyfiPaths.outputInvertEnabled.path);
      if (_outputInvertEnabledAvailable) {
        _outputInvertEnabled = await lyfiDeviceApi.getOutputInvertEnabled(
          boundDevice!.device,
          cancelToken: masterCancellation,
        );
        _initialOutputInvertEnabled = _outputInvertEnabled;
      }

      final channelNames = List<String>.filled(maxChannelCount, '', growable: false);
      final channelColors = List<String>.filled(maxChannelCount, '#FFFFFF', growable: false);
      final channelWavelengths = List<int>.filled(maxChannelCount, 0, growable: false);
      final channelWavelengths2 = List<int>.filled(maxChannelCount, 0, growable: false);
      final channelFractions = List<double>.filled(maxChannelCount, 1.0, growable: false);
      final channelRatios = List<double>.filled(maxChannelCount, 1.0, growable: false);
      for (int channel = 0; channel < maxChannelCount; channel++) {
        channelNames[channel] = await _loadChannelNameFromNvs(channel);
        channelColors[channel] = await _loadChannelColorFromNvs(channel);
        channelWavelengths[channel] = await _loadChannelWavelengthFromNvs(channel);
        channelWavelengths2[channel] = await _loadChannelWavelength2FromNvs(channel);
        channelFractions[channel] = await _loadChannelFractionFromNvs(channel);
        channelRatios[channel] = await _loadChannelRatioFromNvs(channel);
      }

      _channels = List<ChannelSettingsEntry>.generate(
        maxChannelCount,
        (i) => ChannelSettingsEntry(
          index: i,
          name: channelNames[i],
          color: channelColors[i],
          wavelength: channelWavelengths[i],
          wavelength2: channelWavelengths2[i],
          fraction: channelFractions[i],
          ratio: channelRatios[i],
          notifyListeners: notifyListeners,
        ),
        growable: false,
      );
    } catch (error, stackTrace) {
      notifyAppError(
        gt.translate('Failed to load controller settings: {msg}', nArgs: {'msg': error.toString()}),
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  String _defaultChannelName(int channel) => 'CH${channel + 1}';

  Future<String> _loadChannelNameFromNvs(int channel) async {
    final key = 'ch$channel.name';
    final fallback = _defaultChannelName(channel);
    final exists = await this.borneoDeviceApi.factoryNvsExists(boundDevice!.device, 'led', key);
    if (!exists) {
      return fallback;
    }

    final value = await this.borneoDeviceApi.getFactoryNvsString(boundDevice!.device, 'led', key);
    if (!isValidChannelName(value)) {
      return fallback;
    }
    return value;
  }

  Future<String> _loadChannelColorFromNvs(int channel) async {
    final key = 'ch$channel.color';
    const fallback = '#FFFFFF';
    final exists = await this.borneoDeviceApi.factoryNvsExists(boundDevice!.device, 'led', key);
    if (!exists) {
      return fallback;
    }

    final value = await this.borneoDeviceApi.getFactoryNvsString(boundDevice!.device, 'led', key);
    if (value.trim().isEmpty) {
      return fallback;
    }
    return value;
  }

  Future<int> _loadChannelWavelengthFromNvs(int channel) async {
    final key = 'ch$channel.wl';
    const fallback = 0;
    final exists = await this.borneoDeviceApi.factoryNvsExists(boundDevice!.device, 'led', key);
    if (!exists) {
      return fallback;
    }

    return await this.borneoDeviceApi.getFactoryNvsU16(boundDevice!.device, 'led', key);
  }

  Future<int> _loadChannelWavelength2FromNvs(int channel) async {
    final key = 'ch$channel.wl2';
    const fallback = 0;
    final exists = await this.borneoDeviceApi.factoryNvsExists(boundDevice!.device, 'led', key);
    if (!exists) {
      return fallback;
    }

    return await this.borneoDeviceApi.getFactoryNvsU16(boundDevice!.device, 'led', key);
  }

  Future<double> _loadChannelFractionFromNvs(int channel) async {
    final key = 'ch$channel.f';
    const fallback = 1.0;
    final exists = await this.borneoDeviceApi.factoryNvsExists(boundDevice!.device, 'led', key);
    if (!exists) {
      return fallback;
    }

    final bytes = await this.borneoDeviceApi.getFactoryNvsBlob(boundDevice!.device, 'led', key);
    return _float32BytesToDouble(bytes);
  }

  Future<double> _loadChannelRatioFromNvs(int channel) async {
    final key = 'ch$channel.r';
    const fallback = 1.0;
    final exists = await this.borneoDeviceApi.factoryNvsExists(boundDevice!.device, 'led', key);
    if (!exists) {
      return fallback;
    }

    final bytes = await this.borneoDeviceApi.getFactoryNvsBlob(boundDevice!.device, 'led', key);
    return _float32BytesToDouble(bytes);
  }

  static double _float32BytesToDouble(List<int> bytes) {
    final bd = ByteData(4);
    for (int i = 0; i < 4; i++) {
      bd.setUint8(i, bytes[i] & 0xFF);
    }
    return bd.getFloat32(0, Endian.little);
  }

  static Uint8List _doubleToFloat32Bytes(double value) {
    final bd = ByteData(4);
    bd.setFloat32(0, value, Endian.little);
    return bd.buffer.asUint8List(bd.offsetInBytes, 4);
  }

  Future<void> _initSetting<T>(NvsSettingEntry<T> setting, Future<T> Function() getter) async {
    if (await this.borneoDeviceApi.factoryNvsExists(boundDevice!.device, setting.namespace, setting.key)) {
      setting._value = await getter();
      setting._initialValue = setting._value;
      setting.available = true;
    } else {
      setting.available = false;
    }
  }

  Future<void> submit() async {
    try {
      await doSubmit();
    } catch (error) {
      notification.showError("Failed to update controller settings", body: error.toString());
      // Optionally log the error if logging is available in BaseLyfiDeviceViewModel.
      rethrow;
    }
  }

  Future<void> doSubmit() async {
    if (nominalPfdSetting.changed) {
      await this.borneoDeviceApi.setFactoryNvsU16(
        boundDevice!.device,
        nominalPfdSetting.namespace,
        nominalPfdSetting.key,
        nominalPfdSetting.value,
      );
      nominalPfdSetting.reset();
    }

    if (nominalPowerSetting.changed) {
      await this.borneoDeviceApi.setFactoryNvsU16(
        boundDevice!.device,
        nominalPowerSetting.namespace,
        nominalPowerSetting.key,
        nominalPowerSetting.value,
      );
      nominalPowerSetting.reset();
    }

    if (pwmFreq.changed) {
      await this.borneoDeviceApi.setFactoryNvsU16(boundDevice!.device, pwmFreq.namespace, pwmFreq.key, pwmFreq.value);
      pwmFreq.reset();
    }

    if (overpowerEnabled.changed) {
      await this.borneoDeviceApi.setFactoryNvsU8(
        boundDevice!.device,
        overpowerEnabled.namespace,
        overpowerEnabled.key,
        overpowerEnabled.value ? 1 : 0,
      );
      overpowerEnabled.reset();
    }

    if (overpowerCutoff.changed) {
      await this.borneoDeviceApi.setFactoryNvsI32(
        boundDevice!.device,
        overpowerCutoff.namespace,
        overpowerCutoff.key,
        overpowerCutoff.value,
      );
      overpowerCutoff.reset();
    }

    if (overtempEnabled.changed) {
      await this.borneoDeviceApi.setFactoryNvsU8(
        boundDevice!.device,
        overtempEnabled.namespace,
        overtempEnabled.key,
        overtempEnabled.value ? 1 : 0,
      );
      overtempEnabled.reset();
    }

    if (overtempCutoff.changed) {
      await this.borneoDeviceApi.setFactoryNvsU8(
        boundDevice!.device,
        overtempCutoff.namespace,
        overtempCutoff.key,
        overtempCutoff.value,
      );
      overtempCutoff.reset();
    }

    if (channelCountSetting.changed) {
      await this.borneoDeviceApi.setFactoryNvsU8(
        boundDevice!.device,
        channelCountSetting.namespace,
        channelCountSetting.key,
        channelCountSetting.value,
      );
      channelCountSetting.reset();
    }

    if (outputInvertEnabledChanged) {
      await lyfiDeviceApi.setOutputInvertEnabled(
        boundDevice!.device,
        _outputInvertEnabled,
        cancelToken: masterCancellation,
      );
      _initialOutputInvertEnabled = _outputInvertEnabled;
      notifyListeners();
    }

    // Channel metadata updates (name/color)
    for (final channel in _channels) {
      if (channel.nameChanged) {
        await this.borneoDeviceApi.setFactoryNvsString(
          boundDevice!.device,
          "led",
          "ch${channel.index}.name",
          channel.name,
        );
      }

      if (channel.colorChanged) {
        await this.borneoDeviceApi.setFactoryNvsString(
          boundDevice!.device,
          "led",
          "ch${channel.index}.color",
          channel.color,
        );
      }

      if (channel.wavelengthChanged) {
        await this.borneoDeviceApi.setFactoryNvsU16(
          boundDevice!.device,
          "led",
          "ch${channel.index}.wl",
          channel.wavelength,
        );
      }

      if (channel.wavelength2Changed) {
        await this.borneoDeviceApi.setFactoryNvsU16(
          boundDevice!.device,
          "led",
          "ch${channel.index}.wl2",
          channel.wavelength2,
        );
      }

      if (channel.fractionChanged) {
        await this.borneoDeviceApi.setFactoryNvsBlob(
          boundDevice!.device,
          "led",
          "ch${channel.index}.f",
          _doubleToFloat32Bytes(channel.fraction),
        );
      }

      if (channel.ratioChanged) {
        await this.borneoDeviceApi.setFactoryNvsBlob(
          boundDevice!.device,
          "led",
          "ch${channel.index}.r",
          _doubleToFloat32Bytes(channel.ratio),
        );
      }

      if (channel.changed) {
        channel.syncInitial();
      }
    }

    await this.borneoDeviceApi.reboot(boundDevice!.device);
  }
}
