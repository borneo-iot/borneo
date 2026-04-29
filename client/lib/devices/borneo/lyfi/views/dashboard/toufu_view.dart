import 'dart:math' as math;

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:gauge_indicator/gauge_indicator.dart';

const double _kStartAngle = 0.0;
const double _kSweepAngle = math.pi * 1.5;
const double _kRingLineWidth = 7.5;

class DashboardToufu extends StatefulWidget {
  final String title;
  final double value;
  final double maxValue;
  final double minValue;
  final IconData? icon;
  final Widget? center;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? progressColor;
  final LinearGradient? linearGradient;
  final Color? arcColor;
  final List<GaugeSegment> segments;

  DashboardToufu({
    required this.title,
    required this.value,
    required this.center,
    required this.minValue,
    required this.maxValue,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.progressColor,
    this.linearGradient,
    this.arcColor,
    this.segments = const [],
    super.key,
  }) {
    assert(!minValue.isNaN);
    assert(!maxValue.isNaN);
    assert(!value.isNaN);
    assert(maxValue != 0);
    assert(
      progressColor == null || linearGradient == null,
      'Provide either progressColor or linearGradient, not both.',
    );

    final minRounded = minValue.roundToDouble();
    final maxRounded = maxValue.roundToDouble();
    final valueRounded = value.roundToDouble();

    assert(minRounded <= maxRounded);
    assert(valueRounded >= minRounded && valueRounded <= maxRounded);
    assert(segments.every((segment) => !segment.from.isNaN && !segment.to.isNaN));
    assert(segments.every((segment) => segment.from <= segment.to));
    assert(segments.every((segment) => segment.from >= minRounded && segment.to <= maxRounded));
  }

  @override
  State<DashboardToufu> createState() => _DashboardToufuState();
}

class _DashboardToufuState extends State<DashboardToufu> with SingleTickerProviderStateMixin {
  static const Duration _animationDuration = Duration(milliseconds: 1000);

  late final AnimationController _animationController;
  late Animation<double> _percentAnimation;
  late double _currentPercent;

  @override
  void initState() {
    super.initState();
    _currentPercent = _calculatePercent(widget.minValue, widget.maxValue, widget.value);
    _animationController = AnimationController(vsync: this, duration: _animationDuration);
    _percentAnimation = AlwaysStoppedAnimation<double>(_currentPercent);
  }

  @override
  void didUpdateWidget(covariant DashboardToufu oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextPercent = _calculatePercent(widget.minValue, widget.maxValue, widget.value);
    if (nextPercent == _currentPercent) {
      return;
    }

    final previousPercent = _percentAnimation.value;
    _currentPercent = nextPercent;
    _percentAnimation = Tween<double>(
      begin: previousPercent,
      end: nextPercent,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.decelerate));
    _animationController.forward(from: 0);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = widget.backgroundColor ?? cs.surfaceContainer;
    final progColor = widget.progressColor ?? cs.primary;
    final arcColor = widget.arcColor ?? (cs.brightness == Brightness.light ? bgColor.darken() : bgColor.brighten());
    final progressGradient = widget.linearGradient;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, _) {
        final animatedPercent = _animationController.isAnimating ? _percentAnimation.value : _currentPercent;

        return Card(
          margin: const EdgeInsets.all(0),
          color: bgColor,
          elevation: 0,
          child: AspectRatio(
            aspectRatio: 1,
            child: SizedBox(
              height: 200,
              child: LayoutBuilder(
                builder: (context, constraints) => Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      if (widget.icon != null)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) => LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  cs.primary,
                                  (cs.brightness == Brightness.dark ? cs.surfaceBright : cs.surfaceDim).withAlpha(96),
                                ],
                              ).createShader(bounds),
                              child: Icon(widget.icon!, size: constraints.maxWidth * 0.14),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsetsGeometry.all(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(
                                painter: _ArcGradientPercentPainter(
                                  percent: animatedPercent,
                                  backgroundColor: arcColor,
                                  progressGradient: progressGradient,
                                  fallbackProgressColor: progColor,
                                  strokeWidth: _kRingLineWidth,
                                ),
                              ),
                              if (widget.center != null) Center(child: widget.center),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

double _calculatePercent(double minValue, double maxValue, double value) {
  final minRounded = minValue.roundToDouble();
  final maxRounded = maxValue.roundToDouble();
  final valueRounded = value.roundToDouble();
  return maxRounded == minRounded
      ? 1.0
      : ((valueRounded - minRounded) / (maxRounded - minRounded)).clamp(0.0, 1.0).toDouble();
}

class _ArcGradientPercentPainter extends CustomPainter {
  const _ArcGradientPercentPainter({
    required this.percent,
    required this.backgroundColor,
    required this.progressGradient,
    required this.fallbackProgressColor,
    required this.strokeWidth,
  });

  final double percent;
  final Color backgroundColor;
  final LinearGradient? progressGradient;
  final Color fallbackProgressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _kStartAngle, _kSweepAngle, false, backgroundPaint);

    if (percent <= 0) {
      return;
    }

    final progressSweep = _kSweepAngle * percent;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (progressGradient != null && progressGradient!.colors.isNotEmpty) {
      progressPaint.shader = SweepGradient(
        colors: progressGradient!.colors,
        stops: progressGradient!.stops,
        startAngle: _kStartAngle,
        endAngle: _kStartAngle + progressSweep,
        tileMode: TileMode.clamp,
      ).createShader(rect);
    } else {
      progressPaint.color = fallbackProgressColor;
    }

    canvas.drawArc(rect, _kStartAngle, progressSweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _ArcGradientPercentPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressGradient != progressGradient ||
        oldDelegate.fallbackProgressColor != fallbackProgressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
