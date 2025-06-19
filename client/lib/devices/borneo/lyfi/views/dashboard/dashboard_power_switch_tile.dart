import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../view_models/lyfi_view_model.dart';

class DashboardPowerSwitchTile extends StatelessWidget {
  const DashboardPowerSwitchTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<LyfiViewModel, ({bool isOn, bool isBusy, bool isLocked, double overallBrightness, bool canUnlock})>(
      selector: (_, vm) => (
        isOn: vm.isOn,
        isBusy: vm.isBusy.value,
        isLocked: vm.isLocked,
        overallBrightness: vm.overallBrightness,
        canUnlock: vm.canUnlock,
      ),
      builder: (context, props, _) {
        final theme = Theme.of(context);
        final isOn = props.isOn;
        final brightness = (props.overallBrightness * 100).clamp(0, 100).toInt();
        return AspectRatio(
          aspectRatio: 2.0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Container(color: theme.colorScheme.surfaceContainer),

                Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: brightness / 100.0),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeInOut,
                    builder: (context, widthFactor, child) {
                      return FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: widthFactor,
                        child: child,
                      );
                    },
                    child: Container(color: theme.colorScheme.inversePrimary),
                  ),
                ),

                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: (!props.isBusy && props.isLocked)
                        ? () => context.read<LyfiViewModel>().switchPowerOnOff(!isOn)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                        child: Row(
                          key: ValueKey(isOn),
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (!isOn) Icon(Icons.power_settings_new, color: Colors.red, size: 24),
                            if (isOn)
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Center(child: Icon(Icons.power_settings_new, color: Colors.green, size: 24)),
                              ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isOn ? 'ON' : 'OFF',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: isOn ? theme.colorScheme.onSurface : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (isOn)
                                    Text(
                                      '$brightness%',
                                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
