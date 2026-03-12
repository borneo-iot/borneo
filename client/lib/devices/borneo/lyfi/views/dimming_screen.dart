import 'package:borneo_common/io/net/rssi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';

import '../view_models/lyfi_view_model.dart';
import '../view_models/editor/manual_editor_view_model.dart';
import '../view_models/editor/schedule_editor_view_model.dart';
import '../view_models/editor/sun_editor_view_model.dart';
import 'widgets/lyfi_header.dart';
import 'editor/manual_editor_view.dart';
import 'editor/schedule_editor_view.dart';
import 'editor/sun_editor_view.dart';
// screen_top_rounded_container is used inside slider lists

class DimmingAppBar extends StatelessWidget {
  final VoidCallback? onBack;
  const DimmingAppBar({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: false,
      floating: false,
      snap: false,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      centerTitle: true,
      leading: Selector<LyfiViewModel, bool>(
        selector: (context, vm) => vm.isBusy,
        builder: (context, isBusy, child) =>
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: isBusy ? null : onBack),
      ),
      title: Selector<LyfiViewModel, ({LyfiMode mode, bool canSwitch})>(
        selector: (context, vm) => (
          mode: vm.mode,
          canSwitch: vm.isOnline && !vm.isSuspectedOffline && vm.isOn && vm.state == LyfiState.dimming,
        ),
        builder: (context, data, _) {
          return SegmentedButton<LyfiMode>(
            showSelectedIcon: false,
            selected: <LyfiMode>{data.mode},
            segments: [
              ButtonSegment<LyfiMode>(
                value: LyfiMode.manual,
                icon: const Icon(Icons.bar_chart_outlined, size: 20),
                tooltip: context.translate('Manual mode'),
              ),
              ButtonSegment<LyfiMode>(
                value: LyfiMode.scheduled,
                icon: const Icon(Icons.alarm_outlined, size: 20),
                tooltip: context.translate('Scheduled mode'),
              ),
              ButtonSegment<LyfiMode>(
                value: LyfiMode.sun,
                icon: const Icon(Icons.wb_sunny_outlined, size: 20),
                tooltip: context.translate('Sun simulation mode'),
              ),
            ],
            onSelectionChanged: data.canSwitch
                ? (Set<LyfiMode> newSelection) {
                    if (data.mode != newSelection.single) {
                      context.read<LyfiViewModel>().switchMode(newSelection.single);
                    }
                  }
                : null,
          );
        },
      ),
      actions: [
        Selector<LyfiViewModel, RssiLevel?>(
          selector: (_, vm) => vm.rssiLevel,
          builder: (context, rssi, _) => Center(
            child: switch (rssi) {
              null => Icon(Icons.wifi_off, size: 24, color: Theme.of(context).colorScheme.error),
              RssiLevel.strong => const Icon(Icons.wifi_rounded, size: 24),
              RssiLevel.medium => const Icon(Icons.wifi_2_bar_rounded, size: 24),
              RssiLevel.weak => const Icon(Icons.wifi_1_bar_rounded, size: 24),
            },
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

class DimmingScreen extends StatelessWidget {
  static const routeName = '/lyfi/dimming';
  const DimmingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.read<LyfiViewModel>();
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          if (vm.isOnline && !vm.isLocked && !vm.isSuspectedOffline) {
            await vm.toggleLock(true);
          }
          return;
        }
        if (vm.isOnline && !vm.isLocked && !vm.isSuspectedOffline) {
          await vm.toggleLock(true);
        }
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            // CustomScrollView with NeverScrollableScrollPhysics keeps the
            // header slivers pinned while the body itself cannot scroll.
            // The SingleChildScrollView inside each editor view handles local
            // scrolling for just the slider-list area.
            CustomScrollView(
              physics: const NeverScrollableScrollPhysics(),
              slivers: [
                DimmingAppBar(
                  onBack: () async {
                    if (!vm.isLocked && !vm.isSuspectedOffline) {
                      await vm.toggleLock(true);
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                const LyfiBusyIndicatorSliver(),
                const LyfiStatusBannersSliver(),
                const SliverFillRemaining(hasScrollBody: true, child: DimmingView()),
              ],
            ),
            const _ConnectionGuardOverlay(),
          ],
        ),
      ),
    );
  }
}

class DimmingView extends StatelessWidget {
  const DimmingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const EditorHost();
  }
}

class EditorHost extends StatelessWidget {
  const EditorHost({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LyfiViewModel>();
    final state = vm.editorState;

    Widget child;
    switch (state.status) {
      case EditorStatus.loading:
        child = const SizedBox.expand(key: ValueKey('editor-loading'));
        break;
      case EditorStatus.error:
        child = Center(
          key: const ValueKey('editor-error'),
          child: Text(context.translate('Editor initialization failed. Please retry.')),
        );
        break;
      case EditorStatus.ready:
        child = _buildEditor(state);
        break;
      case EditorStatus.idle:
        child = const SizedBox.shrink(key: ValueKey('editor-idle'));
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: child,
    );
  }

  Widget _buildEditor(EditorState state) {
    final editor = state.editor;
    if (editor == null) {
      return const SizedBox.shrink(key: ValueKey('editor-null'));
    }

    switch (state.mode) {
      case LyfiMode.manual:
        return editor is ManualEditorViewModel
            ? ManualEditorView(key: const ValueKey('editor-manual'), viewModel: editor)
            : const SizedBox.shrink(key: ValueKey('editor-manual-mismatch'));
      case LyfiMode.scheduled:
        return editor is ScheduleEditorViewModel
            ? ScheduleEditorView(key: const ValueKey('editor-scheduled'), viewModel: editor)
            : const SizedBox.shrink(key: ValueKey('editor-scheduled-mismatch'));
      case LyfiMode.sun:
        return editor is SunEditorViewModel
            ? SunEditorView(key: const ValueKey('editor-sun'), viewModel: editor)
            : const SizedBox.shrink(key: ValueKey('editor-sun-mismatch'));
    }
  }
}

class _ConnectionGuardOverlay extends StatelessWidget {
  const _ConnectionGuardOverlay();

  @override
  Widget build(BuildContext context) {
    return Selector<LyfiViewModel, _OverlayState>(
      selector: (context, vm) => _OverlayState(
        isOnline: vm.isOnline,
        isSuspectedOffline: vm.isSuspectedOffline,
        isReconnecting: vm.isReconnecting,
        countdownSeconds: vm.reconnectCountdownSeconds,
      ),
      builder: (context, state, child) {
        final showOffline = !state.isOnline;
        final showSuspected = state.isOnline && state.isSuspectedOffline;
        if (!showOffline && !showSuspected) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final message = showOffline
            ? context.translate('Device connection lost. Controls are locked.')
            : context.translate('Connection unstable. Trying to reconnect…');
        final vm = context.read<LyfiViewModel>();
        final showBackToDevice = ModalRoute.of(context)?.settings.arguments == null;
        final rawCountdown = state.countdownSeconds ?? 0;
        final int countdown = rawCountdown < 0 ? 0 : (rawCountdown > 99 ? 99 : rawCountdown);
        final bool isReconnecting = state.isReconnecting;

        return Positioned.fill(
          child: ColoredBox(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
                    ),
                  ),
                  if (showOffline || showSuspected)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: FilledButton.tonalIcon(
                        onPressed: isReconnecting ? null : () => vm.reconnect(),
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          isReconnecting
                              ? '${context.translate("Connecting...")} (${countdown}s)'
                              : context.translate('RETRY'),
                        ),
                      ),
                    ),
                  if (showBackToDevice)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).popUntil((route) {
                            final args = route.settings.arguments;
                            if (args is DeviceEntity) {
                              return true;
                            }
                            return route.isFirst;
                          });
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: Text(context.translate('Back to device')),
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OverlayState {
  final bool isOnline;
  final bool isSuspectedOffline;
  final bool isReconnecting;
  final int? countdownSeconds;

  const _OverlayState({
    required this.isOnline,
    required this.isSuspectedOffline,
    required this.isReconnecting,
    required this.countdownSeconds,
  });
}
