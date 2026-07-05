import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../providers/app_provider.dart';
import '../widgets/glass_card.dart';
import 'ble_search_screen.dart';
import 'device_session_screen.dart';
import 'lan_search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -60,
            right: -60,
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [
                    AppColors.accent.withValues(alpha: isDark ? 0.28 : 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _HeroHeader(isDark: isDark),
                  const Spacer(),
                  Text(
                    'Conectar dispositivo',
                    style: AppTheme.text(
                      context,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppTheme.labelSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ConnectionOptionCard(
                    icon: CupertinoIcons.bluetooth,
                    iconColor: const Color(0xFF0A84FF),
                    iconBg: const Color(0xFF0A84FF).withValues(alpha: 0.14),
                    title: 'Bluetooth',
                    subtitle: 'Emparejar y configurar WiFi del ESP32',
                    onTap: () => _openSearch(context, isBle: true),
                  ),
                  const SizedBox(height: 12),
                  _ConnectionOptionCard(
                    icon: CupertinoIcons.wifi,
                    iconColor: const Color(0xFF30D158),
                    iconBg: const Color(0xFF30D158).withValues(alpha: 0.14),
                    title: 'Red local (LAN)',
                    subtitle: 'Control por WiFi cuando ya está en tu red',
                    onTap: () => _openSearch(context, isBle: false),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Demo',
                    style: AppTheme.text(
                      context,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppTheme.labelSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ConnectionOptionCard(
                    icon: CupertinoIcons.play_circle_fill,
                    iconColor: const Color(0xFFFF9500),
                    iconBg: const Color(0xFFFF9500).withValues(alpha: 0.14),
                    title: 'Modo demo',
                    subtitle: 'Prueba la interfaz sin dispositivo real',
                    onTap: () => _openDemo(context),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Elige Bluetooth la primera vez.\nDespués puedes usar LAN en casa.',
                    textAlign: TextAlign.center,
                    style: AppTheme.text(
                      context,
                      fontSize: 13,
                      height: 1.45,
                      color: AppTheme.labelSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSearch(BuildContext context, {required bool isBle}) async {
    final page = isBle ? const BleSearchScreen() : const LanSearchScreen();
    final opened = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(builder: (_) => page),
    );
    if (opened == true && context.mounted) {
      HapticFeedback.mediumImpact();
      await Navigator.of(context).push(
        CupertinoPageRoute(
          fullscreenDialog: true,
          builder: (_) => const DeviceSessionScreen(),
        ),
      );
    }
  }

  Future<void> _openDemo(BuildContext context) async {
    final app = context.read<AppProvider>();
    await app.openDemoSession();
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => const DeviceSessionScreen(),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A84FF), Color(0xFF5AC8FA)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            CupertinoIcons.drop_fill,
            size: 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 22),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: isDark
                ? const [Colors.white, Color(0xFFB3D9FF)]
                : const [Color(0xFF0D47A1), Color(0xFF1976D2)],
          ).createShader(bounds),
          child: Text(
            'Inodoro Smart',
            textAlign: TextAlign.center,
            style: AppTheme.text(
              context,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Control inteligente de tu baño',
          textAlign: TextAlign.center,
          style: AppTheme.text(
            context,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppTheme.labelSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _ConnectionOptionCard extends StatelessWidget {
  const _ConnectionOptionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      borderRadius: 20,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 26),
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
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppTheme.text(
                    context,
                    fontSize: 13,
                    height: 1.3,
                    color: AppTheme.labelSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: AppTheme.labelSecondary(context).withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}
