import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/ble_provisioning_service.dart';
import '../widgets/device_search_shell.dart';
import 'device_connecting_screen.dart';

class BleSearchScreen extends StatefulWidget {
  const BleSearchScreen({super.key});

  @override
  State<BleSearchScreen> createState() => _BleSearchScreenState();
}

class _BleSearchScreenState extends State<BleSearchScreen> {
  AppProvider? _app;
  String? _connectionError;

  static const _accent = Color(0xFF0A84FF);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= context.read<AppProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppProvider>().scanBle();
    });
  }

  @override
  void dispose() {
    unawaited(_app?.stopBleScan(notify: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        return DeviceSearchShell(
          navTitle: 'Bluetooth',
          heroTitle: 'Buscar por Bluetooth',
          heroSubtitle: 'Encuentra tu INODORO_SMART cerca y conéctate al ESP32.',
          channelIcon: CupertinoIcons.bluetooth,
          accentColor: _accent,
          scanning: app.scanningBle,
          error: app.bleScanError,
          connectionError: _connectionError,
          resultCount: app.bleResults.length,
          emptyMessage:
              'No se encontró ningún dispositivo.\n'
              'Verifica que el ESP32 esté encendido y cerca del teléfono.',
          onRescan: () {
            setState(() => _connectionError = null);
            app.scanBle();
          },
          deviceTiles: app.bleResults
              .map(
                (r) => DeviceSearchTile(
                  title: r.name,
                  subtitle: 'Señal ${r.rssi} dBm',
                  icon: CupertinoIcons.bluetooth,
                  accent: _accent,
                  onTap: () => _select(context, r),
                  trailing: BleSignalBars(rssi: r.rssi),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<void> _select(BuildContext context, BleScanResult result) async {
    final outcome = await Navigator.of(context).push<Object?>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => DeviceConnectingScreen.ble(
          deviceName: result.name,
          device: result.device,
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
