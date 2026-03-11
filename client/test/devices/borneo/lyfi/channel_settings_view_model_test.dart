import 'package:flutter_test/flutter_test.dart';

import 'package:borneo_app/devices/borneo/lyfi/view_models/controller_settings_view_model.dart';

void main() {
  group('channel settings validation', () {
    test('accepts UTF-8 names up to 15 bytes', () {
      expect(isValidChannelName('channel-1234567'), isTrue);
      expect(isValidChannelName('测试测试测试'), isFalse);
    });

    test('rejects blank names', () {
      expect(isValidChannelName(''), isFalse);
      expect(isValidChannelName('   '), isFalse);
    });

    test('accepts wavelength values in uint16 range', () {
      expect(isValidChannelWavelength(0), isTrue);
      expect(isValidChannelWavelength(65535), isTrue);
      expect(isValidChannelWavelength(-1), isFalse);
      expect(isValidChannelWavelength(65536), isFalse);
    });

    test('draft exposes the same validation rules used by the parent model', () {
      const draft = ChannelSettingsDraft(name: 'foo', color: '#112233', wavelength: 450);
      const invalidDraft = ChannelSettingsDraft(name: '', color: '#112233', wavelength: 70000);

      expect(draft.nameValid, isTrue);
      expect(draft.wavelengthValid, isTrue);
      expect(invalidDraft.nameValid, isFalse);
      expect(invalidDraft.wavelengthValid, isFalse);
    });
  });
}
