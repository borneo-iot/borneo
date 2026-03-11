import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/devices/borneo/lyfi/views/spectrum_chart.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canRenderSpectrumChart', () {
    test('requires at least one channel and all wavelengths >= 380', () {
      expect(canRenderSpectrumChart(const []), isFalse);
      expect(
        canRenderSpectrumChart(const [
          LyfiChannelInfo(name: 'UV', color: '#ffffff', wavelength: 370, brightnessRatio: 1.0),
        ]),
        isFalse,
      );
      expect(
        canRenderSpectrumChart(const [
          LyfiChannelInfo(name: 'Blue', color: '#0000ff', wavelength: 450, brightnessRatio: 1.0),
          LyfiChannelInfo(name: 'White', color: '#ffffff', wavelength: 4000, brightnessRatio: 1.0),
        ]),
        isTrue,
      );
    });
  });

  group('buildSpectrumSpots', () {
    test('adds white-light contribution for color temperature channels', () {
      final spots = buildSpectrumSpots(
        channels: const [LyfiChannelInfo(name: 'White', color: '#ffffff', wavelength: 4000, brightnessRatio: 1.0)],
        brightnessValues: const [kLyfiBrightnessMax],
      );

      expect(spots, isNotEmpty);
      expect(spots.any((spot) => spot.y > 0.01), isTrue);
      final maxSpot = spots.reduce((current, next) => current.y >= next.y ? current : next);
      expect(maxSpot.x, inInclusiveRange(430.0, 680.0));
    });
  });

  testWidgets('LyfiSpectrumChart renders a line chart for spectrum-capable channels', (tester) async {
    final brightnessValues = [ValueNotifier(kLyfiBrightnessMax), ValueNotifier(kLyfiBrightnessMax ~/ 2)];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 150,
            child: LyfiSpectrumChart(
              channels: const [
                LyfiChannelInfo(name: 'Blue', color: '#0000ff', wavelength: 450, brightnessRatio: 1.0),
                LyfiChannelInfo(name: 'White', color: '#ffffff', wavelength: 5600, brightnessRatio: 1.0),
              ],
              brightnessValues: brightnessValues,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsOneWidget);

    for (final notifier in brightnessValues) {
      notifier.dispose();
    }
  });
}
