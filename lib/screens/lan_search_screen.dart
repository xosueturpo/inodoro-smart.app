import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/discovery_service.dart';
import '../widgets/device_search_shell.dart';
import 'device_connecting_screen.dart';

class LanSearchScreen extends StatefulWidget {
  const LanSearchScreen({super.key});

  @override
  State<LanSearchScreen> createState() => _LanSearchScreenState();
}

class _LanSearchScreenState extends State<LanSearchScreen> {
  AppProvider? _app;
  String? _connectionError;

  static const _accent = Color(0xFF30D158);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= context.read<AppProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppProvider>().scanLan();
    });
  }

  @override
  void dispose() {
    unawaited(_app?.stopLanScan(notify: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        return DeviceSearchShell(
          navTitle: 'WiFi LAN',
          heroTitle: 'Buscar en la red',
          heroSubtitle:
              'Tu teléfono y el ESP32 deben estar en la misma red WiFi.',
          channelIcon: CupertinoIcons.wifi,
          accentColor: _accent,
          scanning: app.scanningLan,
          error: app.lanScanError,
          connectionError: _connectionError,
          resultCount: app.lanResults.length,
          emptyMessage:
              'No se encontró inodoro_smart en la red.\n'
              'Configura WiFi del ESP32 por Bluetooth primero.',
          onRescan: () {
            setState(() => _connectionError = null);
            app.scanLan();
          },
          deviceTiles: app.lanResults
              .map(
                (r) => DeviceSearchTile(
                  title: r.name,
                  subtitle: r.host,
                  icon: CupertinoIcons.wifi,
                  accent: _accent,
                  onTap: () => _select(context, r),
                  trailing: LanHostBadge(host: r.host),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<void> _select(BuildContext context, DiscoveryResult result) async {
    final outcome = await Navigator.of(context).push<Object?>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => DeviceConnectingScreen.lan(
          deviceName: result.name,
          host: result.host,
        ),
      ),
    );

    if (!mounted) return;

    if (outcome == true) {
      if (!context.mounted) return;
      Navigator.of(context).pop(true);
      return;
    }

    if (outcome is String) {
      setState(() => _connectionError = outcome);
    }
  }
}
