import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:logger/logger.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/features/devices/widgets/dashboard_tile.dart';

import '../../view_models/lyfi_view_model.dart';
import '../dimming_screen.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';

class DashboardDimmingTile extends StatelessWidget {
  const DashboardDimmingTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<LyfiViewModel, bool>(
      selector: (_, vm) => vm.canUnlock,
      builder: (context, canUnlock, _) {
        final theme = Theme.of(context);
        final isDisabled = !canUnlock;
        final Color bgColor = theme.colorScheme.surfaceContainerHighest;
        final Color fgColor = theme.colorScheme.onSurface;
        final double disabledAlpha = 0.38;
        final Color effectiveFgColor = isDisabled ? fgColor.withValues(alpha: disabledAlpha) : fgColor;
        final Color iconColor = theme.colorScheme.primary;
        final Color effectiveIconColor = isDisabled ? iconColor.withValues(alpha: disabledAlpha) : iconColor;
        return DashboardTile(
          backgroundColor: bgColor,
          disabled: !(canUnlock && context.read<LyfiViewModel>().isOnline),
          onPressed: (canUnlock && context.read<LyfiViewModel>().isOnline) ? () => _onTilePressed(context) : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Selector<LyfiViewModel, LyfiMode>(
                selector: (_, vm) => vm.mode,
                builder: (context, mode, _) {
                  final modeIcon = switch (mode) {
                    LyfiMode.manual => Icons.tune_outlined,
                    LyfiMode.scheduled => Icons.auto_graph_outlined,
                    LyfiMode.sun => Icons.wb_sunny_outlined,
                  };
                  return Icon(modeIcon, size: 32, color: effectiveIconColor);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.translate('Dimming'),
                      style: theme.textTheme.titleMedium?.copyWith(color: effectiveFgColor),
                    ),
                    Selector<LyfiViewModel, LyfiMode>(
                      selector: (_, vm) => vm.mode,
                      builder: (context, mode, _) {
                        final modeText = switch (mode) {
                          LyfiMode.manual => context.translate('Manual'),
                          LyfiMode.scheduled => context.translate('Scheduled'),
                          LyfiMode.sun => context.translate('Sun Simulation'),
                        };
                        return Text(modeText, style: theme.textTheme.bodySmall?.copyWith(color: effectiveFgColor));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onTilePressed(BuildContext context) async {
    final vm = context.read<LyfiViewModel>();
    try {
      // Request entering dimming (unlock) then wait for readiness event-driven
      await vm.toggleLock(false);
      await vm.onDimmingReady();
      if (context.mounted) {
        await pushScreen(
          context,
          screen: ChangeNotifierProvider.value(value: vm, child: const DimmingScreen()),
          withNavBar: false,
          pageTransitionAnimation: PageTransitionAnimation.platform,
        );
      }
    } catch (error, stackTrace) {
      if (context.mounted) {
        context.read<Logger>().e(error.toString(), error: error, stackTrace: stackTrace);
        vm.notifyAppError(context.translate('Failed to open dimming page: {msg}', nArgs: {'msg': error.toString()}));
      }
    }
  }
}
