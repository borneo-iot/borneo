import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/events.dart';
import '../view_models/lyfi_view_model.dart';

class DiscoPage extends StatefulWidget {
  const DiscoPage({super.key});

  @override
  State<DiscoPage> createState() => _DiscoPageState();
}

class _DiscoPageState extends State<DiscoPage> with SingleTickerProviderStateMixin {
  StreamSubscription<LyfiStateChangedEvent>? _stateChangedSub;
  late AnimationController _animationController;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();

    // hide system UI (status bar & navigation) while this page is visible
    // ImmersiveSticky works on both Android and iOS to suppress bottom nav
    // When we pop the page dispose() will restore the default mode.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Initialize animation controller but don't start yet
    _animationController = AnimationController(vsync: this, duration: const Duration(seconds: 3));

    // Delay animation start to allow page transition to complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animationController.repeat();
      }
    });

    // Subscribe to state changes
    final vm = context.read<LyfiViewModel>();
    _stateChangedSub = vm.deviceManager.allDeviceEvents.on<LyfiStateChangedEvent>().listen((event) {
      if (vm.deviceEntity.id == event.device.id) {
        // If state changed away from disco, close the page
        if (event.state != LyfiState.disco && mounted && !_isExiting) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    // restore system UI overlays when leaving
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _stateChangedSub?.cancel();
    _stateChangedSub = null;
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _exitDiscoMode() async {
    await _exitDiscoModeAndMaybePop(shouldPop: true);
  }

  Future<void> _exitDiscoModeAndMaybePop({required bool shouldPop}) async {
    if (_isExiting) return;
    _isExiting = true;

    // Stop animation first
    _animationController.stop();

    final vm = context.read<LyfiViewModel>();
    if (vm.state == LyfiState.disco) {
      vm.switchDiscoState();
    }

    if (shouldPop && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          await _exitDiscoModeAndMaybePop(shouldPop: false);
          return;
        }
        await _exitDiscoModeAndMaybePop(shouldPop: true);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _exitDiscoMode,
          child: Container(
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _DiscoPainter(_animationController.value),
                  child: const Center(child: Icon(Icons.nightlife, size: 120, color: Colors.white70)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoPainter extends CustomPainter {
  final double animationValue;

  _DiscoPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final screenRadius = math.min(size.width, size.height) / 2 * 0.9;

    // Draw multiple colorful circles with animation
    for (int i = 0; i < 8; i++) {
      final angle = (animationValue * 2 * math.pi) + (i * math.pi / 4);
      final radius = screenRadius * 0.2 * (1 + 0.5 * math.sin(animationValue * 2 * math.pi + i));
      final offset = Offset(
        center.dx + math.cos(angle) * screenRadius * 0.5,
        center.dy + math.sin(angle) * screenRadius * 0.5,
      );

      final hue = (animationValue * 360 + i * 45) % 360;
      final color = HSVColor.fromAHSV(0.3, hue, 1.0, 1.0).toColor();

      final paint = Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

      canvas.drawCircle(offset, radius, paint);
    }

    // Draw center gradient burst
    final gradient = RadialGradient(
      colors: [
        HSVColor.fromAHSV(0.5, (animationValue * 360) % 360, 1.0, 1.0).toColor(),
        HSVColor.fromAHSV(0.3, (animationValue * 360 + 120) % 360, 1.0, 1.0).toColor(),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final rect = Rect.fromCircle(center: center, radius: screenRadius * 0.7);
    final paint = Paint()..shader = gradient.createShader(rect);

    canvas.drawCircle(center, screenRadius * 0.7, paint);

    // Draw rotating rainbow ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    for (int i = 0; i < 360; i += 10) {
      final startAngle = (i + animationValue * 360) % 360;
      final color = HSVColor.fromAHSV(0.8, startAngle, 1.0, 1.0).toColor();
      ringPaint.color = color;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: screenRadius * 0.6),
        (startAngle * math.pi / 180),
        (10 * math.pi / 180),
        false,
        ringPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DiscoPainter oldDelegate) => true;
}
