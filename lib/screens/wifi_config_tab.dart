import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/device_models.dart';
import '../providers/app_provider.dart';
import '../services/wifi_scan_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/ios_buttons.dart';

class WifiConfigTab extends StatefulWidget {
  const WifiConfigTab({super.key});

  @override
  State<WifiConfigTab> createState() => _WifiConfigTabState();
}

class _WifiConfigTabState extends State<WifiConfigTab> {
  final _wifiScan = WifiScanService();

  bool _busy = false;
  bool _scanning = false;
  String? _feedback;
  List<WifiNetworkResult> _networks = [];
  bool _hasScanned = false;

  Future<void> _scanNetworks() async {
    setState(() {
      _scanning = true;
      _feedback = null;
    });
    try {
      final results = await _wifiScan.scanNetworks();
      if (!mounted) return;
      setState(() {
        _networks = results;
        _hasScanned = true;
        if (results.isEmpty) {
          _feedback =
              'No se encontraron redes. Prueba "Configurar manualmente".';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _networks = [];
        _hasScanned = true;
        _feedback = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _provision(
    AppProvider app,
    String ssid,
    String password,
  ) async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await app.provisionWifi(ssid, password);
      if (!mounted) return;
      setState(() => _feedback = 'Conectando ESP32 a $ssid…');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onNetworkSelected(
    AppProvider app,
    WifiNetworkResult network,
  ) async {
    if (_busy || _scanning || !app.canSendCommands) return;

    if (!network.secure) {
      final connect = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(network.ssid),
          content: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Esta red está abierta. ¿Conectar sin contraseña?'),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Conectar'),
            ),
          ],
        ),
      );
      if (connect == true && mounted) {
        await _provision(app, network.ssid, '');
      }
      return;
    }

    final password = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => _WifiPasswordSheet(ssid: network.ssid),
    );

    if (password != null && mounted) {
      await _provision(app, network.ssid, password);
    }
  }

  Future<void> _showManualForm(AppProvider app) async {
    if (_busy || _scanning || !app.canSendCommands) return;

    final credentials = await showCupertinoModalPopup<({String ssid, String pass})>(
      context: context,
      builder: (ctx) => const _ManualWifiSheet(),
    );

    if (credentials != null && mounted) {
      await _provision(app, credentials.ssid, credentials.pass);
    }
  }

  Future<void> _reset(AppProvider app) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Borrar WiFi'),
        content: const Text(
          'Se eliminarán las credenciales guardadas en el ESP32.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await app.resetWifi();
      if (!mounted) return;
      setState(() {
        _networks = [];
        _hasScanned = false;
        _feedback = 'WiFi borrado del ESP32';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedback = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final status = app.wifiStatus ?? EspWifiStatus.unknown();
        final enabled = app.canSendCommands && !_busy && !_scanning;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _WifiStatusCard(
              status: status,
              onRefresh: enabled ? app.refreshWifiStatus : null,
            ),
            const SizedBox(height: 24),
            IosPrimaryButton(
              label: _scanning ? 'Buscando redes…' : 'Buscar redes WiFi',
              icon: CupertinoIcons.wifi,
              isLoading: _scanning,
              onPressed: enabled ? _scanNetworks : null,
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Center(child: CupertinoActivityIndicator(radius: 14)),
            if (!_hasScanned && !_scanning && !_busy) ...[
              const SizedBox(height: 32),
              Icon(
                CupertinoIcons.wifi,
                size: 48,
                color: AppTheme.labelSecondary(context).withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Toca buscar para ver las redes\ncercanas y conectar el ESP32',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.labelSecondary(context),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
            if (_networks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_networks.length} redes encontradas',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.labelSecondary(context),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                padding: EdgeInsets.zero,
                borderRadius: 16,
                child: Column(
                  children: [
                    for (var i = 0; i < _networks.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 52,
                          color: AppTheme.isDark(context)
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                        ),
                      _NetworkTile(
                        network: _networks[i],
                        enabled: enabled,
                        onTap: () => _onNetworkSelected(app, _networks[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onPressed: enabled ? () => _showManualForm(app) : null,
                child: Text(
                  'Configurar manualmente',
                  style: TextStyle(
                    fontSize: 15,
                    color: enabled
                        ? AppColors.accent
                        : AppTheme.labelSecondary(context),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
            Center(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                onPressed: enabled ? () => _reset(app) : null,
                child: Text(
                  'Borrar WiFi del ESP32',
                  style: TextStyle(
                    fontSize: 14,
                    color: enabled
                        ? AppColors.danger
                        : AppTheme.labelSecondary(context),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              Text(
                _feedback!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.labelSecondary(context),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Modal: contraseña para red protegida.
class _WifiPasswordSheet extends StatefulWidget {
  const _WifiPasswordSheet({required this.ssid});

  final String ssid;

  @override
  State<_WifiPasswordSheet> createState() => _WifiPasswordSheetState();
}

class _WifiPasswordSheetState extends State<_WifiPasswordSheet> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    HapticFeedback.lightImpact();
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final isDark = AppTheme.isDark(context);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.labelSecondary(context).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(CupertinoIcons.lock_shield, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.ssid,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.labelPrimary(context),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Introduce la contraseña de la red',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.labelSecondary(context),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: _controller,
                placeholder: 'Contraseña',
                obscureText: _obscure,
                autofocus: true,
                padding: const EdgeInsets.all(14),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                suffix: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _obscure = !_obscure),
                  child: Icon(
                    _obscure ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    size: 20,
                    color: AppTheme.labelSecondary(context),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              IosPrimaryButton(
                label: 'Conectar ESP32',
                icon: CupertinoIcons.checkmark,
                onPressed: _submit,
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal: SSID y contraseña manual.
class _ManualWifiSheet extends StatefulWidget {
  const _ManualWifiSheet();

  @override
  State<_ManualWifiSheet> createState() => _ManualWifiSheetState();
}

class _ManualWifiSheetState extends State<_ManualWifiSheet> {
  final _ssidController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return;
    HapticFeedback.lightImpact();
    Navigator.pop(context, (ssid: ssid, pass: _passController.text));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final isDark = AppTheme.isDark(context);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.labelSecondary(context).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Configuración manual',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.labelPrimary(context),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Escribe el SSID y la contraseña de la red',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.labelSecondary(context),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoTextField(
                controller: _ssidController,
                placeholder: 'Nombre de red (SSID)',
                autofocus: true,
                padding: const EdgeInsets.all(14),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: _passController,
                placeholder: 'Contraseña (vacío si es abierta)',
                obscureText: _obscure,
                padding: const EdgeInsets.all(14),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                suffix: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _obscure = !_obscure),
                  child: Icon(
                    _obscure ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    size: 20,
                    color: AppTheme.labelSecondary(context),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              IosPrimaryButton(
                label: 'Guardar y conectar',
                icon: CupertinoIcons.wifi,
                onPressed: _submit,
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.network,
    required this.enabled,
    required this.onTap,
  });

  final WifiNetworkResult network;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onPressed: enabled ? onTap : null,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              network.secure ? CupertinoIcons.lock_fill : CupertinoIcons.wifi,
              color: AppColors.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  network.ssid,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.labelPrimary(context),
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  network.secure ? 'Protegida' : 'Abierta',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.labelSecondary(context),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          _SignalBars(bars: network.signalBars),
          const SizedBox(width: 8),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: AppTheme.labelSecondary(context),
          ),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars});

  final int bars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final active = i < bars;
        return Container(
          width: 4,
          height: 6.0 + i * 4,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent
                : AppTheme.labelSecondary(context).withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

class _WifiStatusCard extends StatelessWidget {
  const _WifiStatusCard({
    required this.status,
    this.onRefresh,
  });

  final EspWifiStatus status;
  final VoidCallback? onRefresh;

  Color _stateColor() {
    return switch (status.state) {
      EspWifiState.connected => AppColors.success,
      EspWifiState.connecting => AppColors.warning,
      EspWifiState.failed => AppColors.danger,
      EspWifiState.configured => AppColors.accent,
      EspWifiState.none => AppColors.warning,
    };
  }

  IconData _stateIcon() {
    return switch (status.state) {
      EspWifiState.connected => CupertinoIcons.wifi,
      EspWifiState.connecting => CupertinoIcons.wifi_exclamationmark,
      EspWifiState.failed => CupertinoIcons.wifi_slash,
      _ => CupertinoIcons.wifi,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_stateIcon(), color: _stateColor(), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Estado WiFi del ESP32',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.labelPrimary(context),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (onRefresh != null)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onRefresh,
                  child: const Icon(CupertinoIcons.arrow_clockwise, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Estado', value: status.stateLabel),
          if (status.ssid != null)
            _InfoRow(label: 'Red', value: status.ssid!),
          if (status.ip != null) _InfoRow(label: 'IP', value: status.ip!),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.labelSecondary(context),
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.labelPrimary(context),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
