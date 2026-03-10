import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/features/devices/widgets/dashboard_tile.dart';

import '../../view_models/lyfi_view_model.dart';
import '../acclimation_screen.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';

class DashboardAcclimationTile extends StatelessWidget {
  const DashboardAcclimationTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
      LyfiViewModel,
      ({bool isOnline, bool isOn, bool enabled, bool activated, AcclimationSettings? acclimation})
    >(
      selector: (_, vm) => (
        isOnline: vm.isOnline,
        isOn: vm.isOn,
        enabled: vm.acclimationEnabled,
        activated: vm.acclimationActivated,
        acclimation: vm.acclimationSettings,
      ),
      builder: (context, props, _) {
        final theme = Theme.of(context);
        final acclimation = props.acclimation;
        final isActive = props.enabled || props.activated;
        final isDisabled = !props.isOnline || !props.isOn;
        final Color bgColor = isActive ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest;
        final Color fgColor = isActive ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface;
        final double disabledAlpha = 0.38;
        final Color effectiveFgColor = isDisabled ? fgColor.withValues(alpha: disabledAlpha) : fgColor;
        final Color iconColor = isActive ? theme.colorScheme.onPrimary : theme.colorScheme.primary;
        final Color effectiveIconColor = isDisabled ? iconColor.withValues(alpha: disabledAlpha) : iconColor;

        // Calculate progress and remaining time
        double progress = 0.0;
        String remainingText = '';
        if (isActive && acclimation != null && acclimation.days > 0) {
          final now = DateTime.now().toUtc();
          final elapsed = now.difference(acclimation.startTimestamp);
          final total = Duration(days: acclimation.days);
          progress = elapsed.inSeconds / total.inSeconds;
          if (progress > 1.0) progress = 1.0;
          final remaining = total - elapsed;
          if (remaining.isNegative) {
            remainingText = '00:00';
          } else {
            final remainingSeconds = remaining.inSeconds;
            if (remainingSeconds < 60) {
              final min = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
              final sec = (remainingSeconds % 60).toString().padLeft(2, '0');
              remainingText = '$min:$sec';
            } else if (remainingSeconds < 24 * 3600) {
              final hours = remaining.inHours;
              final mins = (remaining.inMinutes % 60);
              remainingText = '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
            } else {
              final days = remaining.inDays;
              final hours = (remaining.inHours % 24);
              remainingText = '${days}d ${hours}h';
            }
          }
        }

        return DashboardTile(
          backgroundColor: bgColor,
          disabled: !props.isOnline || !props.isOn,
          onPressed: props.isOnline && props.isOn
              ? () async {
                  if (context.mounted) {
                    final vm = context.read<LyfiViewModel>();
                    final deviceID = vm.deviceID;
                    await PersistentNavBarNavigator.pushNewScreen(
                      context,
                      screen: ChangeNotifierProvider.value(
                        value: vm,
                        child: AcclimationScreen(deviceID: deviceID),
                      ),
                      withNavBar: false,
                    );
                  }
                }
              : null,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                    child: isActive
                        ? SizedBox(
                            key: const ValueKey('active'),
                            width: 32,
                            height: 32,
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeAlign: 1,
                                strokeWidth: 2,
                                value: progress,
                                backgroundColor: theme.colorScheme.shadow,
                                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.onPrimaryContainer),
                              ),
                            ),
                          )
                        : Container(
                            key: const ValueKey('inactive'),
                            alignment: Alignment.center,
                            child: Icon(Icons.calendar_month_outlined, size: 32, color: effectiveIconColor),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.translate("Acclimation"),
                          style: theme.textTheme.titleMedium?.copyWith(color: effectiveFgColor),
                        ),
                        if (isActive && remainingText.isNotEmpty)
                          Text(
                            remainingText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: effectiveFgColor,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isActive)
                Positioned(
                  right: -16,
                  bottom: -16,
                  child: Icon(
                    Icons.calendar_month_outlined,
                    size: 64,
                    color: theme.colorScheme.inversePrimary.withValues(alpha: 0.24),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
