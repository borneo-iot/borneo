import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';

import 'package:borneo_app/devices/borneo/lyfi/view_models/controller_settings_view_model.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/dimmer_channel_view.dart';
import '../../../mocks/mocks.dart';

// Localizations delegate used throughout the tests to satisfy
// widgets that call `context.translate()`.
class _FakeGettextDelegate extends LocalizationsDelegate<GettextLocalizations> {
  const _FakeGettextDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GettextLocalizations> load(Locale locale) async => FakeGettext();

  @override
  bool shouldReload(covariant LocalizationsDelegate<GettextLocalizations> old) => false;
}

void main() {
  testWidgets('DimmerChannelView returns edited draft on save', (tester) async {
    BuildContext? navigatorContext;
    final nameField = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == 'Name');
    final wavelengthField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Wavelength',
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [_FakeGettextDelegate()],
        supportedLocales: const [Locale('en', 'US')],
        home: Builder(
          builder: (context) {
            navigatorContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    await tester.pump();

    final resultFuture = Navigator.of(navigatorContext!).push<ChannelSettingsDraft>(
      MaterialPageRoute(
        builder: (_) => const DimmerChannelView(
          initialValue: ChannelSettingsDraft(name: 'ch1', color: '#FFFFFF', wavelength: 450),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(nameField, findsOneWidget);
    expect(wavelengthField, findsOneWidget);
    expect(find.byType(ColorPicker), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Save').evaluate().single.widget, isA<TextButton>());

    await tester.enterText(nameField, '');
    await tester.pumpAndSettle();
    final disabledSave = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
    expect(disabledSave.onPressed, isNull);

    await tester.enterText(nameField, 'foo');
    await tester.enterText(wavelengthField, '660');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result, isNotNull);
    expect(result!.name, equals('foo'));
    expect(result.color, equals('#FFFFFF'));
    expect(result.wavelength, equals(660));
  });

  testWidgets('DimmerChannelView wavelength field accepts zero and rejects negative input', (tester) async {
    BuildContext? navigatorContext;
    final wavelengthField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Wavelength',
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [_FakeGettextDelegate()],
        supportedLocales: const [Locale('en', 'US')],
        home: Builder(
          builder: (context) {
            navigatorContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    await tester.pump();

    Navigator.of(navigatorContext!).push<void>(
      MaterialPageRoute(
        builder: (_) => const DimmerChannelView(
          initialValue: ChannelSettingsDraft(name: 'ch1', color: '#FFFFFF', wavelength: 450),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final wavelengthTextField = tester.widget<TextField>(wavelengthField);
    expect(wavelengthTextField.inputFormatters, isNotNull);
    expect(wavelengthTextField.decoration?.hintText, equals('0 - 65535'));

    final formatter = wavelengthTextField.inputFormatters!.single;
    const oldValue = TextEditingValue(text: '450');

    expect(formatter.formatEditUpdate(oldValue, const TextEditingValue(text: '0')).text, equals('0'));
    expect(formatter.formatEditUpdate(oldValue, const TextEditingValue(text: '-1')).text, equals('1'));
    expect(formatter.formatEditUpdate(oldValue, const TextEditingValue(text: '123')).text, equals('123'));
  });
}
