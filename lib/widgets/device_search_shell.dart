import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import 'glass_card.dart';

/// Shell visual compartido para pantallas de búsqueda BLE / LAN.
class DeviceSearchShell extends StatefulWidget {
  const DeviceSearchShell({
    super.key,
    required this.navTitle,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.channelIcon,
    required this.accentColor,
    required this.scanning,
    required this.error,
    required this.resultCount,
    required this.emptyMessage,
    required this.onRescan,
    required this.deviceTiles,
    this.connectionError,
  });

  final String navTitle;
  final String heroTitle;
  final String heroSubtitle;
  final IconData channelIcon;
  final Color accentColor;
  final bool scanning;
  final String? error;
  final String? connectionError;
  final int resultCount;
  final String emptyMessage;
  final VoidCallback onRescan;
  final List<Widget> deviceTiles;

  @override
  State<DeviceSearchShell> createState() => _DeviceSearchShellState();
}

class _DeviceSearchShellState extends State<DeviceSearchShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(DeviceSearchShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scanning != widget.scanning) _syncPulse();
  }

  void _syncPulse() {
    if (widget.scanning) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.navTitle),
        border: null,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: -40,
            right: -40,
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.85,
                  colors: [
                    widget.accentColor.withValues(alpha: isDark ? 0.28 : 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                  children: [
                      _SearchHero(
                        icon: widget.channelIcon,
                        accent: widget.accentColor,
                        title: widget.heroTitle,
                        subtitle: widget.heroSubtitle,
                        scanning: widget.scanning,
                        pulse: _pulse,
                      ),
                      const SizedBox(height: 20),
                      _StatusChip(
                        scanning: widget.scanning,
                        resultCount: widget.resultCount,
                        accent: widget.accentColor,
                      ),
                      if (widget.connectionError != null) ...[
                        const SizedBox(height: 14),
                        _ErrorBanner(
                          title: 'No se pudo conectar',
                          message: widget.connectionError!,
                        ),
                      ],
                      if (widget.error != null) ...[
                        const SizedBox(height: 14),
                        _ErrorBanner(message: widget.error!),
                      ],
                      const SizedBox(height: 16),
                      if (widget.deviceTiles.isNotEmpty)
                        ...widget.deviceTiles
                      else if (!widget.scanning) ...[
                        const SizedBox(height: 12),
                        _EmptyState(
                          icon: widget.channelIcon,
                          message: widget.emptyMessage,
                          accent: widget.accentColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: SafeArea(
              top: false,
              child: _RescanButton(
                scanning: widget.scanning,
                accent: widget.accentColor,
                onPressed: widget.onRescan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHero extends StatelessWidget {
  const _SearchHero({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.scanning,
    required this.pulse,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final bool scanning;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 112,
          height: 112,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (scanning) ...[
                    _PulseRing(
                      progress: pulse.value,
                      accent: accent,
                      scale: 1.0,
                    ),
                    _PulseRing(
                      progress: (pulse.value + 0.35) % 1.0,
                      accent: accent,
                      scale: 1.18,
                    ),
                  ],
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accent, Color.lerp(accent, Colors.white, 0.35)!],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 34),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTheme.text(
            context,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTheme.text(
            context,
            fontSize: 15,
            height: 1.35,
            color: AppTheme.labelSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({
    required this.progress,
    required this.accent,
    required this.scale,
  });

  final double progress;
  final Color accent;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = 72.0 * scale * (0.85 + progress * 0.45);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: accent.withValues(alpha: (1 - progress) * 0.45),
          width: 2,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.scanning,
    required this.resultCount,
    required this.accent,
  });

  final bool scanning;
  final int resultCount;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final label = scanning
        ? 'Buscando dispositivos…'
        : resultCount == 0
            ? 'Sin resultados por ahora'
            : resultCount == 1
                ? '1 dispositivo encontrado'
                : '$resultCount dispositivos encontrados';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (scanning)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CupertinoActivityIndicator(radius: 8, color: accent),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  resultCount > 0
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.search,
                  size: 16,
                  color: accent,
                ),
              ),
            Text(
              label,
              style: AppTheme.text(
                context,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    this.title = 'Error',
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: AppColors.danger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.text(
                    context,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: AppTheme.text(
                    context,
                    fontSize: 14,
                    height: 1.35,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.accent,
  });

  final IconData icon;
  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          Icon(
            icon,
            size: 44,
            color: accent.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.text(
              context,
              fontSize: 15,
              height: 1.45,
              color: AppTheme.labelSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _RescanButton extends StatelessWidget {
  const _RescanButton({
    required this.scanning,
    required this.accent,
    required this.onPressed,
  });

  final bool scanning;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 16),
      color: accent,
      borderRadius: BorderRadius.circular(16),
      onPressed: scanning
          ? null
          : () {
              HapticFeedback.lightImpact();
              onPressed();
            },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (scanning)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: CupertinoActivityIndicator(color: Colors.white),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(CupertinoIcons.arrow_clockwise, color: Colors.white, size: 20),
            ),
          Text(
            scanning ? 'Buscando…' : 'Buscar de nuevo',
            style: AppTheme.text(
              context,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de dispositivo para listas de búsqueda.
class DeviceSearchTile extends StatelessWidget {
  const DeviceSearchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.connecting = false,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool connecting;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: connecting ? null : onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: 18,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.text(
                      context,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.text(
                      context,
                      fontSize: 13,
                      color: AppTheme.labelSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            if (connecting)
              const CupertinoActivityIndicator(radius: 10)
            else if (trailing != null)
              trailing!
            else
              Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: AppTheme.labelSecondary(context).withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }
}

/// Barras de señal para RSSI BLE.
class BleSignalBars extends StatelessWidget {
  const BleSignalBars({super.key, required this.rssi});

  final int rssi;

  int get _bars {
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -80) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < _bars;
        final h = 6.0 + i * 4;
        return Container(
          width: 4,
          height: h,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent
                : AppTheme.labelSecondary(context).withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

/// Etiqueta LAN con host.
class LanHostBadge extends StatelessWidget {
  const LanHostBadge({super.key, required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        host,
        style: AppTheme.text(
          context,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.success,
        ),
      ),
    );
  }
}
