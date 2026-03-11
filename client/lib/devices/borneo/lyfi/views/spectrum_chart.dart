import 'dart:math';

import 'package:borneo_app/devices/borneo/lyfi/view_models/constants.dart';
import 'package:borneo_app/shared/widgets/value_listenable_builders.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

const double kSpectrumChartMinX = 380;
const double kSpectrumChartMaxX = 800;
const double _kSpectrumAxisIntervalX = 100;
const double _kSpectrumSampleStep = 4;
const double _kVisibleChannelFwhm = 20;
const double _kInfraredChannelFwhm = 34;
const Duration _kSpectrumAnimationDuration = Duration(milliseconds: 120);

final LinearGradient _kSpectrumGradient = _buildSpectrumGradient();

bool canRenderSpectrumChart(Iterable<LyfiChannelInfo> channels) {
  final channelList = channels.toList(growable: false);
  return channelList.isNotEmpty && channelList.every((channel) => channel.wavelength >= kSpectrumChartMinX);
}

List<FlSpot> buildSpectrumSpots({
  required List<LyfiChannelInfo> channels,
  required List<int> brightnessValues,
  double sampleStep = _kSpectrumSampleStep,
}) {
  final cache = _SpectrumChartCache.create(channels: channels, sampleStep: sampleStep);
  return _buildSpectrumSpotsFromCache(cache: cache, brightnessValues: brightnessValues);
}

class LyfiSpectrumChart extends StatefulWidget {
  final List<LyfiChannelInfo> channels;
  final List<ValueNotifier<int>> brightnessValues;

  const LyfiSpectrumChart({super.key, required this.channels, required this.brightnessValues});

  @override
  State<LyfiSpectrumChart> createState() => _LyfiSpectrumChartState();
}

class _LyfiSpectrumChartState extends State<LyfiSpectrumChart> {
  late _SpectrumChartCache _cache;

  @override
  void initState() {
    super.initState();
    _cache = _SpectrumChartCache.create(channels: widget.channels, sampleStep: _kSpectrumSampleStep);
  }

  @override
  void didUpdateWidget(covariant LyfiSpectrumChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasSameChannelDescriptors(oldWidget.channels, widget.channels)) {
      _cache = _SpectrumChartCache.create(channels: widget.channels, sampleStep: _kSpectrumSampleStep);
    }
  }

  bool _hasSameChannelDescriptors(List<LyfiChannelInfo> previous, List<LyfiChannelInfo> current) {
    if (identical(previous, current)) {
      return true;
    }
    if (previous.length != current.length) {
      return false;
    }
    for (int index = 0; index < previous.length; index++) {
      final left = previous[index];
      final right = current[index];
      if (left.wavelength != right.wavelength || left.color != right.color || left.name != right.name) {
        return false;
      }
    }
    return true;
  }

  FlTitlesData _buildTitles(BuildContext context) {
    final xAxisTicks = <double>[400, 500, 600, 700, 800];
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
      fontSize: 9,
    );
    return FlTitlesData(
      show: true,
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: _kSpectrumAxisIntervalX,
          getTitlesWidget: (value, meta) {
            if (!xAxisTicks.contains(value.roundToDouble())) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              child: Text(value.toInt().toString(), style: labelStyle),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          interval: 0.25,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text('${(value * 100).round()}%', style: labelStyle),
          ),
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  FlGridData _buildGrid(BuildContext context) {
    final gridColor = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55);
    return FlGridData(
      show: true,
      drawVerticalLine: true,
      horizontalInterval: 0.25,
      verticalInterval: _kSpectrumAxisIntervalX,
      getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1, dashArray: const [1, 2]),
      getDrawingVerticalLine: (_) => FlLine(color: gridColor, strokeWidth: 1, dashArray: const [1, 2]),
    );
  }

  FlBorderData _buildBorder(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.85);
    return FlBorderData(
      show: true,
      border: Border(
        left: BorderSide(color: borderColor, width: 1),
        bottom: BorderSide(color: borderColor, width: 1),
        top: BorderSide(color: borderColor, width: 1),
        right: BorderSide(color: borderColor, width: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiValueListenableBuilder<int>(
      valueNotifiers: widget.brightnessValues,
      builder: (context, values, _) {
        final spots = _buildSpectrumSpotsFromCache(cache: _cache, brightnessValues: values);
        return LineChart(
          LineChartData(
            minX: kSpectrumChartMinX,
            maxX: kSpectrumChartMaxX,
            minY: 0,
            maxY: 1,
            titlesData: _buildTitles(context),
            gridData: _buildGrid(context),
            borderData: _buildBorder(context),
            lineTouchData: const LineTouchData(enabled: true),
            clipData: const FlClipData.all(),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                curveSmoothness: 0.18,
                barWidth: 1,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, gradient: _kSpectrumGradient),
              ),
            ],
          ),
          duration: _kSpectrumAnimationDuration,
        );
      },
    );
  }
}

class _SpectrumChartCache {
  final List<double> sampleWavelengths;
  final List<List<double>> channelProfiles;
  final List<FlSpot> emptySpots;

  _SpectrumChartCache._({required this.sampleWavelengths, required this.channelProfiles, required this.emptySpots});

  factory _SpectrumChartCache.create({required List<LyfiChannelInfo> channels, required double sampleStep}) {
    final sampleWavelengths = _buildSampleWavelengths(sampleStep: sampleStep);
    final channelProfiles = channels
        .map(
          (channel) => sampleWavelengths
              .map((wavelength) => _channelContribution(channel.wavelength.toDouble(), wavelength, 1.0))
              .toList(growable: false),
        )
        .toList(growable: false);
    final emptySpots = sampleWavelengths.map((wavelength) => FlSpot(wavelength, 0)).toList(growable: false);
    return _SpectrumChartCache._(
      sampleWavelengths: sampleWavelengths,
      channelProfiles: channelProfiles,
      emptySpots: emptySpots,
    );
  }
}

List<FlSpot> _buildSpectrumSpotsFromCache({required _SpectrumChartCache cache, required List<int> brightnessValues}) {
  final itemCount = min(cache.channelProfiles.length, brightnessValues.length);
  if (itemCount == 0) {
    return cache.emptySpots;
  }

  final combinedIntensities = List<double>.filled(cache.sampleWavelengths.length, 0, growable: false);
  double maxIntensity = 0;

  for (int channelIndex = 0; channelIndex < itemCount; channelIndex++) {
    final brightness = (brightnessValues[channelIndex] / kLyfiBrightnessMax).clamp(0.0, 1.0).toDouble();
    if (brightness <= 0) {
      continue;
    }
    final profile = cache.channelProfiles[channelIndex];
    for (int sampleIndex = 0; sampleIndex < profile.length; sampleIndex++) {
      final intensity = combinedIntensities[sampleIndex] + (profile[sampleIndex] * brightness);
      combinedIntensities[sampleIndex] = intensity;
      if (intensity > maxIntensity) {
        maxIntensity = intensity;
      }
    }
  }

  if (maxIntensity <= 0) {
    return cache.emptySpots;
  }

  final normalizer = max(1.0, maxIntensity);
  return List<FlSpot>.generate(
    cache.sampleWavelengths.length,
    (index) => FlSpot(cache.sampleWavelengths[index], combinedIntensities[index] / normalizer),
    growable: false,
  );
}

List<double> _buildSampleWavelengths({required double sampleStep}) {
  final wavelengths = <double>[];
  for (double wavelength = kSpectrumChartMinX; wavelength <= kSpectrumChartMaxX; wavelength += sampleStep) {
    wavelengths.add(wavelength);
  }
  return wavelengths;
}

LinearGradient _buildSpectrumGradient() {
  final wavelengths = List<double>.generate(43, (index) => kSpectrumChartMinX + (index * 10.0));
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: wavelengths.map(_colorForSpectrumWavelength).toList(growable: false),
    stops: wavelengths.map(_wavelengthStop).toList(growable: false),
  );
}

double _wavelengthStop(double wavelength) {
  return ((wavelength - kSpectrumChartMinX) / (kSpectrumChartMaxX - kSpectrumChartMinX)).clamp(0.0, 1.0);
}

Color _colorForSpectrumWavelength(double wavelength) {
  final clampedWavelength = wavelength.clamp(kSpectrumChartMinX, kSpectrumChartMaxX);
  double red;
  double green;
  double blue;

  if (clampedWavelength < 440) {
    red = -(clampedWavelength - 440) / (440 - 380);
    green = 0;
    blue = 1;
  } else if (clampedWavelength < 490) {
    red = 0;
    green = (clampedWavelength - 440) / (490 - 440);
    blue = 1;
  } else if (clampedWavelength < 510) {
    red = 0;
    green = 1;
    blue = -(clampedWavelength - 510) / (510 - 490);
  } else if (clampedWavelength < 580) {
    red = (clampedWavelength - 510) / (580 - 510);
    green = 1;
    blue = 0;
  } else if (clampedWavelength < 645) {
    red = 1;
    green = -(clampedWavelength - 645) / (645 - 580);
    blue = 0;
  } else {
    red = 1;
    green = 0;
    blue = 0;
  }

  final factor = switch (clampedWavelength) {
    >= 380 && < 420 => 0.3 + 0.7 * ((clampedWavelength - 380) / (420 - 380)),
    >= 420 && <= 700 => 1.0,
    > 700 && <= 780 => 0.3 + 0.7 * ((780 - clampedWavelength) / (780 - 700)),
    _ => 0.18,
  };

  return Color.fromRGBO(
    _gammaCorrectColor(red, factor),
    _gammaCorrectColor(green, factor),
    _gammaCorrectColor(blue, factor),
    1,
  );
}

int _gammaCorrectColor(double channel, double factor) {
  if (channel <= 0) {
    return 0;
  }
  final corrected = pow(channel * factor, 0.8).toDouble() * 255;
  return corrected.round().clamp(0, 255);
}

double _channelContribution(double descriptor, double sampleWavelength, double intensity) {
  if (descriptor > 1000) {
    return _whiteLightContribution(descriptor, sampleWavelength, intensity);
  }
  if (descriptor > kSpectrumChartMaxX) {
    return _infraredEdgeContribution(descriptor, sampleWavelength, intensity);
  }
  return _gaussianContribution(
    center: descriptor,
    sampleWavelength: sampleWavelength,
    intensity: intensity,
    fwhm: _kVisibleChannelFwhm,
  );
}

double _gaussianContribution({
  required double center,
  required double sampleWavelength,
  required double intensity,
  required double fwhm,
}) {
  final sigma = fwhm / (2 * sqrt(2 * log(2)));
  final exponent = -pow(sampleWavelength - center, 2) / (2 * pow(sigma, 2));
  return intensity * exp(exponent);
}

double _infraredEdgeContribution(double wavelength, double sampleWavelength, double intensity) {
  final visibility = ((1000 - wavelength) / 200).clamp(0.08, 0.9).toDouble();
  return _gaussianContribution(
    center: kSpectrumChartMaxX - 8,
    sampleWavelength: sampleWavelength,
    intensity: intensity * visibility,
    fwhm: _kInfraredChannelFwhm,
  );
}

double _whiteLightContribution(double kelvin, double sampleWavelength, double intensity) {
  final rgb = _kelvinToRgb(kelvin);
  final redWeight = rgb.r;
  final greenWeight = rgb.g;
  final blueWeight = rgb.b;
  final continuum = _gaussianContribution(
    center: 560,
    sampleWavelength: sampleWavelength,
    intensity: intensity * (0.22 + ((redWeight + greenWeight + blueWeight) / 3) * 0.28),
    fwhm: 180,
  );
  final bluePeak = _gaussianContribution(
    center: 455,
    sampleWavelength: sampleWavelength,
    intensity: intensity * (0.12 + blueWeight * 0.46),
    fwhm: 64,
  );
  final greenPeak = _gaussianContribution(
    center: 545,
    sampleWavelength: sampleWavelength,
    intensity: intensity * (0.14 + greenWeight * 0.40),
    fwhm: 88,
  );
  final redPeak = _gaussianContribution(
    center: 625,
    sampleWavelength: sampleWavelength,
    intensity: intensity * (0.18 + redWeight * 0.52),
    fwhm: 108,
  );
  final farRedPeak = _gaussianContribution(
    center: 680,
    sampleWavelength: sampleWavelength,
    intensity: intensity * (0.08 + redWeight * 0.22),
    fwhm: 72,
  );
  return continuum + bluePeak + greenPeak + redPeak + farRedPeak;
}

Color _kelvinToRgb(double kelvin) {
  final temperature = (kelvin / 100).clamp(10.0, 400.0);
  final red = temperature <= 66 ? 255.0 : 329.698727446 * pow(temperature - 60, -0.1332047592).toDouble();
  final green = temperature <= 66
      ? 99.4708025861 * log(temperature) - 161.1195681661
      : 288.1221695283 * pow(temperature - 60, -0.0755148492).toDouble();
  final blue = temperature >= 66
      ? 255.0
      : temperature <= 19
      ? 0.0
      : 138.5177312231 * log(temperature - 10) - 305.0447927307;

  return Color.fromRGBO(red.clamp(0, 255).round(), green.clamp(0, 255).round(), blue.clamp(0, 255).round(), 1);
}
