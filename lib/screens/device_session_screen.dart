import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/device_models.dart';
import '../providers/app_provider.dart';
import '../widgets/flush_control.dart';
import '../widgets/tank_refill_button.dart';
import '../widgets/lid_open_button.dart';
import '../widgets/lid_close_button.dart';
import '../widgets/voice_command_fab.dart';
import '../widgets/ios_buttons.dart';
import '../widgets/link_status_pill.dart';
import '../widgets/voice_assistant_bubble.dart';
import 'wifi_config_tab.dart';

class DeviceSessionScreen extends StatefulWidget {
  const DeviceSessionScreen({super.key});

  @override
  State<DeviceSessionScreen> createState() => _DeviceSessionScreenState();
}

class _DeviceSessionScreenState extends State<DeviceSessionScreen> {
  int _tabIndex = 0;
  bool _closing = false;

  Future<void> _close(BuildContext context) async {
    if (_closing) return;
    _closing = true;

    final app = context.read<AppProvider>();
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(app.closeSession());
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_closing) {
          unawaited(_close(context));
        }
      },
      child: CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navigationBar: CupertinoNavigationBar(
          middle: Consumer<AppProvider>(
            builder: (_, app, _) => Text(
              app.session?.deviceName ?? 'Inodoros Fuertes',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _close(context),
            child: const Text('Cerrar'),
          ),
        ),
        child: SafeArea(
          child: _closing
              ? const Center(child: CupertinoActivityIndicator())
              : Consumer<AppProvider>(
            builder: (context, app, _) {
              final session = app.session;
              if (session == null) {
                return const Center(child: CupertinoActivityIndicator());
              }

              final showTabs = app.isBleSession;

              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _SessionHeader(
                          session: session,
                          app: app,
                          showStatusPill: !showTabs || _tabIndex == 0,
                        ),
                      ),
                      Expanded(
                        child: showTabs
                            ? IndexedStack(
                                index: _tabIndex,
                                children: const [
                                  _ControlTab(),
                                  WifiConfigTab(),
                                ],
                              )
                            : const _ControlTab(),
                      ),
                      if (showTabs)
                        _BottomTabs(
                          index: _tabIndex,
                          onChanged: (i) {
                            setState(() => _tabIndex = i);
                            if (i == 1) {
                              context.read<AppProvider>().refreshWifiStatus();
                            }
                          },
                        ),
                    ],
                  ),
                  if (session.linkState == SessionLinkState.connected &&
                      !app.isDemoSession &&
                      app.voice.showAssistantBubble)
                    VoiceAssistantBubble(
                      state: app.voice.state,
                      transcript: app.voice.lastHeard,
                      resultMessage: app.voice.lastAction,
                      micLevel: app.voice.micLevel,
                      micSessionOpen: app.voice.micSessionOpen,
                    ),
                  if (session.linkState == SessionLinkState.connected &&
                      !app.isDemoSession)
                    Positioned(
                      right: 20,
                      bottom: showTabs ? 72 : 24,
                      child: VoiceCommandFab(
                        state: app.voice.state,
                        enabled: !app.deviceBusy,
                        onPressed: () => app.startVoiceCommand(),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.session,
    required this.app,
    required this.showStatusPill,
  });

  final DeviceSession session;
  final AppProvider app;
  final bool showStatusPill;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showStatusPill)
          LinkStatusPill(
            linkState: session.linkState,
            channel: session.channel,
          ),
        if (session.lastError != null &&
            session.linkState == SessionLinkState.error &&
            session.channel != ConnectionChannel.demo) ...[
          const SizedBox(height: 10),
          Text(
            session.lastError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.danger,
              fontSize: 13,
              decoration: TextDecoration.none,
            ),
          ),
        ],
        if (session.linkState == SessionLinkState.error &&
            session.channel != ConnectionChannel.demo) ...[
          const SizedBox(height: 12),
          IosSecondaryButton(
            label: 'Reconectar',
            icon: CupertinoIcons.arrow_2_circlepath,
            onPressed: app.reconnectNow,
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      child: Row(
        children: [
          _TabItem(
            selected: index == 0,
            icon: CupertinoIcons.drop_fill,
            label: 'Control',
            onTap: () => onChanged(0),
          ),
          _TabItem(
            selected: index == 1,
            icon: CupertinoIcons.wifi,
            label: 'Configurar WiFi',
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppTheme.labelSecondary(context);

    return Expanded(
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 10),
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlTab extends StatelessWidget {
  const _ControlTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final session = app.session;
        if (session == null) return const SizedBox.shrink();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Control del inodoro',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.labelPrimary(context),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 16),
              FlushControl(
                enabled: app.canSendCommands || app.deviceBusy,
                flushing: app.flushInProgress,
                refilling: app.refillInProgress,
                onFlush: app.canSendCommands ? app.sendFlushCommand : null,
              ),
              const SizedBox(height: 12),
              TankRefillButton(
                enabled: app.canSendCommands,
                busy: app.deviceBusy,
                onRefill: app.canSendCommands ? app.sendRefillCommand : null,
              ),
              const SizedBox(height: 12),
              LidOpenButton(
                enabled: app.canOpenLid,
                flushing: app.flushInProgress,
                refilling: app.refillInProgress,
                onOpen: app.canOpenLid ? app.sendLidOpenCommand : null,
              ),
              const SizedBox(height: 12),
              LidCloseButton(
                enabled: app.canCloseLid,
                flushing: app.flushInProgress,
                refilling: app.refillInProgress,
                onClose: app.canCloseLid ? app.sendLidCloseCommand : null,
              ),
              const SizedBox(height: 20),
              Text(
                switch (session.channel) {
                  ConnectionChannel.demo =>
                    'Modo demo · descarga y recarga simuladas (3 s)',
                  ConnectionChannel.ble => 'Bluetooth · reconexión cada 5 s',
                  _ => 'WiFi LAN · reconexión cada 5 s',
                },
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.labelSecondary(context),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
