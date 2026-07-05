import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Botón gráfico de descarga + animación de agua mientras `flushing`.
class FlushControl extends StatefulWidget {
  const FlushControl({
    super.key,
    required this.enabled,
    required this.flushing,
    this.refilling = false,
    this.onFlush,
  });

  final bool enabled;
  final bool flushing;
  final bool refilling;
  final VoidCallback? onFlush;

  @override
  State<FlushControl> createState() => _FlushControlState();
}

class _FlushControlState extends State<FlushControl>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  bool _controllersReady = false;

  @override
  void initState() {
    super.initState();
    _initController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAnimation();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    if (_controllersReady) {
      _controller?.dispose();
    }
    _initController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAnimation();
    });
  }

  void _initController() {
    _controller?.dispose();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _controllersReady = true;
  }

  @override
  void didUpdateWidget(FlushControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flushing != widget.flushing ||
        oldWidget.refilling != widget.refilling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncAnimation();
      });
    }
  }

  void _syncAnimation() {
    final c = _controller;
    if (c == null) return;

    if (widget.flushing || widget.refilling) {
      if (!c.isAnimating) c.repeat();
    } else {
      c
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.enabled || widget.flushing || widget.refilling) return;
    HapticFeedback.mediumImpact();
    widget.onFlush?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final controller = _controller;

    final busy = widget.flushing || widget.refilling;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.refilling
              ? const [Color(0xFF006064), Color(0xFF00838F), Color(0xFF4DD0E1)]
              : widget.flushing
              ? const [Color(0xFF0047AB), Color(0xFF007AFF), Color(0xFF5AC8FA)]
              : widget.enabled
                  ? const [Color(0xFF0066CC), Color(0xFF0A84FF), Color(0xFF64D2FF)]
                  : const [
                      Color(0xFF6B7280),
                      Color(0xFF9CA3AF),
                      Color(0xFFCBD5E1),
                    ],
        ),
        boxShadow: [
          BoxShadow(
            color: (widget.refilling
                    ? const Color(0xFF00BCD4)
                    : const Color(0xFF0A84FF))
                .withValues(alpha: widget.enabled || busy ? 0.35 : 0.08),
            blurRadius: busy ? 28 : 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.28),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(28),
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: SizedBox(
              height: busy ? 224 : 200,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.hardEdge,
                children: [
                  if (busy && controller != null)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: controller,
                        builder: (context, child) => CustomPaint(
                          painter: _FlushWaterPainter(progress: controller.value),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 80,
                              width: 80,
                              child: controller == null
                                  ? const SizedBox.shrink()
                                  : AnimatedBuilder(
                                      animation: controller,
                                      builder: (context, child) => CustomPaint(
                                        painter: _ToiletIconPainter(
                                          flushing: widget.flushing,
                                          refilling: widget.refilling,
                                          progress: controller.value,
                                          enabled: widget.enabled,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 320),
                              child: widget.flushing
                                  ? _FlushingLabel(progress: controller?.value ?? 0)
                                  : widget.refilling
                                      ? _RefillingLabel(progress: controller?.value ?? 0)
                                      : _IdleLabel(enabled: widget.enabled),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.flushing
                                  ? 'Descargando · servo y buzzer activos'
                                  : widget.refilling
                                      ? 'Recargando tanque · relé activo'
                                      : 'También con la mano a 5 cm del sensor',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.82),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
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
  }
}

class _IdleLabel extends StatelessWidget {
  const _IdleLabel({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Descargar baño',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Colors.white.withValues(alpha: enabled ? 1 : 0.65),
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          enabled ? 'Toca para activar la descarga' : 'Espera a que termine…',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.88),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class _FlushingLabel extends StatelessWidget {
  const _FlushingLabel({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final dots = '.' * (1 + (progress * 3).floor() % 4);

    return Column(
      key: const ValueKey('flushing'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Descargando$dots',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: const LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Color(0x38FFFFFF),
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _RefillingLabel extends StatelessWidget {
  const _RefillingLabel({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final dots = '.' * (1 + (progress * 3).floor() % 4);

    return Column(
      key: const ValueKey('refilling'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Recargando tanque$dots',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: const LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Color(0x38FFFFFF),
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToiletIconPainter extends CustomPainter {
  _ToiletIconPainter({
    required this.flushing,
    required this.refilling,
    required this.progress,
    required this.enabled,
  });

  final bool flushing;
  final bool refilling;
  final double progress;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;

    final bodyPaint = Paint()
      ..color = Colors.white.withValues(alpha: enabled ? 0.95 : 0.55)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final tank = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 22, 4, 44, 28),
      const Radius.circular(8),
    );
    canvas.drawRRect(tank, bodyPaint);
    canvas.drawRRect(tank, stroke);

    canvas.drawCircle(Offset(cx, 14), 5.5, Paint()..color = const Color(0xFF5AC8FA));
    if (flushing) {
      final dropY = 14 + (progress * 34) % 34;
      canvas.drawCircle(
        Offset(cx, dropY),
        3.2,
        Paint()..color = const Color(0xFF5AC8FA).withValues(alpha: 0.85),
      );
    }

    final bowlPath = Path()
      ..moveTo(cx - 34, 38)
      ..quadraticBezierTo(cx - 34, 72, cx, 78)
      ..quadraticBezierTo(cx + 34, 72, cx + 34, 38)
      ..close();
    canvas.drawPath(bowlPath, bodyPaint);
    canvas.drawPath(bowlPath, stroke);

    final waterLevel = flushing
        ? 52 + math.sin(progress * math.pi * 2) * 3
        : refilling
            ? 54 + math.sin(progress * math.pi * 2) * 1.5
            : 58.0;
    final waterAlpha = flushing ? 0.85 : refilling ? 0.7 : 0.55;
    final waterRect = Rect.fromLTWH(cx - 28, waterLevel, 56, 78 - waterLevel);
    canvas.drawRRect(
      RRect.fromRectAndRadius(waterRect, const Radius.circular(10)),
      Paint()..color = const Color(0xFF5AC8FA).withValues(alpha: waterAlpha),
    );

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 10, waterLevel + 8), width: 14, height: 6),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _ToiletIconPainter oldDelegate) =>
      oldDelegate.flushing != flushing ||
      oldDelegate.refilling != refilling ||
      oldDelegate.progress != progress ||
      oldDelegate.enabled != enabled;
}

class _FlushWaterPainter extends CustomPainter {
  _FlushWaterPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.55;

    for (var i = 0; i < 3; i++) {
      final phase = (progress + i * 0.28) % 1.0;
      final radius = 20 + phase * 90;
      final alpha = (1 - phase) * 0.28;
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }

    final bubblePaint = Paint()..color = Colors.white.withValues(alpha: 0.45);
    for (var i = 0; i < 8; i++) {
      final seed = i * 0.13;
      final x = cx + math.sin((progress + seed) * math.pi * 2) * (38 + i * 4);
      final y = size.height - ((progress + seed) % 1.0) * size.height * 0.75;
      final r = 2.0 + (i % 3);
      canvas.drawCircle(Offset(x, y), r, bubblePaint);
    }

    final wavePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    for (var band = 0; band < 2; band++) {
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width; x += 6) {
        final y = size.height * (0.18 + band * 0.08) +
            math.sin((x / size.width * 4 * math.pi) +
                    (progress + band * 0.2) * 2 * math.pi) *
                8;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, wavePaint);
    }

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 80));
    canvas.drawCircle(Offset(cx, cy), 80, glow);
  }

  @override
  bool shouldRepaint(covariant _FlushWaterPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
