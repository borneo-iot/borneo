import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/features/devices/widgets/dashboard_tile.dart';

import '../../view_models/lyfi_view_model.dart';

class DashboardPowerSwitchTile extends StatelessWidget {
  const DashboardPowerSwitchTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
      LyfiViewModel,
      ({bool isOn, bool isBusy, bool isLocked, double overallBrightness, bool canUnlock, bool isOnline})
    >(
      selector: (_, vm) => (
        isOn: vm.isOn,
        isBusy: vm.isBusy,
        isLocked: vm.isLocked,
        overallBrightness: vm.overallBrightness,
        canUnlock: vm.canUnlock,
        isOnline: vm.isOnline,
      ),
      builder: (context, props, _) {
        final theme = Theme.of(context);
        final isOn = props.isOn;
        final brightness = (props.overallBrightness * 100).clamp(0, 100).toInt();
        final isOnline = props.isOnline;
        final isDisabled = !isOnline || props.isBusy || !props.isLocked;
        final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);

        return DashboardTile(
          backgroundOverlay: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: brightness / 100.0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOut,
              builder: (context, widthFactor, child) {
                return FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: widthFactor, child: child);
              },
              child: Container(color: isDisabled ? disabledColor : theme.colorScheme.inversePrimary),
            ),
          ),
          disabled: isDisabled,
          onPressed: (!props.isBusy && props.isLocked && isOnline)
              ? () => context.read<LyfiViewModel>().switchPowerOnOff(!isOn)
              : null,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: Row(
              key: ValueKey(isOn),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isOn) Icon(Icons.power_settings_new, color: isDisabled ? disabledColor : Colors.red, size: 32),
                if (isOn)
                  SizedBox(
                    height: 32,
                    width: 32,
                    child: Center(
                      child: Icon(Icons.power_settings_new, color: isDisabled ? disabledColor : Colors.green, size: 32),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOn ? context.translate('ON') : context.translate('OFF'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: isDisabled ? disabledColor : (isOn ? theme.colorScheme.onSurface : Colors.red),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isOn)
                        Text(
                          '$brightness%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDisabled ? disabledColor : theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
