import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/device_models.dart';
import '../providers/app_provider.dart';

/// Pantalla a pantalla completa mientras se establece la conexión.
/// Devuelve `true` si conectó, o un [String] con el mensaje de error.
class DeviceConnectingScreen extends StatefulWidget {
  const DeviceConnectingScreen.ble({
    super.key,
    required this.deviceName,
    required this.device,
  })  : channel = ConnectionChannel.ble,
        host = null;

  const DeviceConnectingScreen.lan({
    super.key,
    required this.deviceName,
    required this.host,
  })  : channel = ConnectionChannel.lan,
        device = null;

  final ConnectionChannel channel;
  final String deviceName;
  final BluetoothDevice? device;
  final String? host;

  @override
  State<DeviceConnectingScreen> createState() => _DeviceConnectingScreenState();
}

class _DeviceConnectingScreenState extends State<DeviceConnectingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _started = false;

  Color get _accent => widget.channel == ConnectionChannel.ble
      ? const Color(0xFF0A84FF)
      : const Color(0xFF30D158);

  IconData get _icon => widget.channel == ConnectionChannel.ble
      ? CupertinoIcons.bluetooth
      : CupertinoIcons.wifi;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_started) return;
    _started = true;

    final app = context.read<AppProvider>();

    try {
      if (widget.channel == ConnectionChannel.ble) {
        await app.openBleSession(widget.device!, widget.deviceName);
      } else {
        await app.openLanSession(widget.host!, widget.deviceName);
      }

      if (!mounted) return;

      if (app.hasActiveSession &&
          app.session?.linkState == SessionLinkState.connected) {
        Navigator.of(context).pop(true);
        return;
      }

      final msg = app.session?.lastError ?? 'No se pudo conectar al dispositivo';
      await app.closeSession(notify: false);
      if (mounted) Navigator.of(context).pop(msg);
    } catch (e) {
      await app.closeSession(notify: false);
      if (mounted) {
        Navigator.of(context).pop(
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -80,
            left: -60,
            right: -60,
            child: Container(
              height: 360,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [
                    _accent.withValues(alpha: isDark ? 0.32 : 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                _ConnectingHero(
                  accent: _accent,
                  icon: _icon,
                  pulse: _pulse,
                ),
                const SizedBox(height: 32),
                Text(
                  'Conectando',
                  style: AppTheme.text(
                    context,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    widget.deviceName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.text(
                      context,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.labelPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.channel == ConnectionChannel.ble
                      ? 'Estableciendo enlace Bluetooth…'
                      : 'Verificando dispositivo en la red…',
                  textAlign: TextAlign.center,
                  style: AppTheme.text(
                    context,
                    fontSize: 15,
                    color: AppTheme.labelSecondary(context),
                  ),
                ),
                const Spacer(flex: 3),
                const CupertinoActivityIndicator(radius: 14),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectingHero extends StatelessWidget {
  const _ConnectingHero({
    required this.accent,
    required this.icon,
    required this.pulse,
  });

  final Color accent;
  final IconData icon;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _Ring(progress: pulse.value, accent: accent, scale: 1.0),
              _Ring(progress: (pulse.value + 0.33) % 1.0, accent: accent, scale: 1.2),
              _Ring(progress: (pulse.value + 0.66) % 1.0, accent: accent, scale: 1.4),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, Color.lerp(accent, Colors.white, 0.35)!],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 38),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.progress,
    required this.accent,
    required this.scale,
  });

  final double progress;
  final Color accent;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = 80.0 * scale * (0.9 + progress * 0.5);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: accent.withValues(alpha: (1 - progress) * 0.5),
          width: 2.5,
        ),
      ),
    );
  }
}
