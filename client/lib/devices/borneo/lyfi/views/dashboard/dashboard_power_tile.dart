import 'package:borneo_app/devices/borneo/lyfi/views/dashboard/toufu_view.dart';
import 'package:community_material_icon/community_material_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:provider/provider.dart';
import '../../view_models/lyfi_view_model.dart';
import '../widgets/rolling_integer.dart';

class DashboardPowerTile extends StatelessWidget {
  const DashboardPowerTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
      LyfiViewModel,
      ({bool isOnline, bool isOn, bool canMeasureVoltage, bool canMeasureCurrent, bool canMeasurePower})
    >(
      selector: (_, vm) => (
        isOnline: vm.isOnline,
        isOn: vm.isOn,
        canMeasureVoltage: vm.canMeasureVoltage,
        canMeasureCurrent: vm.canMeasureCurrent,
        canMeasurePower: vm.canMeasurePower,
      ),
      builder: (context, props, _) {
        final theme = Theme.of(context);
        final vm = context.read<LyfiViewModel>();
        final mergedListenable = Listenable.merge([vm.currentVoltage, vm.currentCurrent, vm.currentWatts]);
        final bool isOnline = props.isOnline;
        final disabledColor = theme.colorScheme.onSurface.withValues(alpha: 0.38);
        final Color fgColor = theme.colorScheme.onSurface;
        final Color arcColor = theme.colorScheme.surfaceDim;
        //final Color progressColor = isOnline ? theme.colorScheme.primary : disabledColor;
        final Color textPrimary = theme.colorScheme.primary;
        final Color textOnSurface = theme.colorScheme.onSurface;
        final LinearGradient progressGradient = LinearGradient(
          colors: [theme.colorScheme.tertiary, theme.colorScheme.primary],
        );
        return ListenableBuilder(
          listenable: mergedListenable,
          builder: (context, _) => DashboardToufu(
            title: context.translate("LED Power"),
            icon: CommunityMaterialIcons.lightning_bolt_outline,
            foregroundColor: isOnline ? fgColor : disabledColor,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            arcColor: arcColor,
            linearGradient: progressGradient,
            minValue: 0.0,
            maxValue: isOnline ? vm.nominalPower ?? 99999 : 99999,
            value: props.canMeasurePower && isOnline ? vm.currentWatts.value ?? 0 : 0,
            center: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  mainAxisAlignment: MainAxisAlignment.center,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (props.canMeasurePower && isOnline)
                      ...() {
                        final double watts = vm.currentWatts.value!;
                        final int intPart = watts.round();
                        final String powerStr = intPart.toString().padLeft(3, '0');
                        final List<String> digits = powerStr.split('');
                        final List<Widget> digitWidgets = [];
                        for (int i = 0; i < digits.length; i++) {
                          final String digit = digits[i];
                          final bool isLeadingZero =
                              i < digits.length - 1 && digit == '0' && digits.sublist(0, i).every((c) => c == '0');
                          final Color color = isLeadingZero ? arcColor : textPrimary;
                          digitWidgets.add(
                            RollingInteger(
                              value: int.parse(digit),
                              textStyle: theme.textTheme.headlineLarge?.copyWith(
                                color: color,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                              duration: const Duration(milliseconds: 200),
                            ),
                          );
                        }
                        return [
                          ...digitWidgets,
                          Text(
                            'W',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: textPrimary,
                            ),
                          ),
                        ];
                      }()
                    else ...[
                      Text(
                        context.translate("N/A"),
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: theme.colorScheme.outlineVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
                if (props.canMeasurePower && isOnline) ...[
                  const Divider(height: 6, thickness: 1, indent: 24, endIndent: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (props.canMeasureVoltage && isOnline)
                        Text(
                          '${vm.currentVoltage.value!.toStringAsFixed(1)}V',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textOnSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      if (props.canMeasureCurrent && isOnline) const SizedBox(width: 4),
                      if (props.canMeasureCurrent && isOnline)
                        Text("·", style: theme.textTheme.bodySmall?.copyWith(color: textOnSurface)),
                      if (props.canMeasureCurrent && isOnline) const SizedBox(width: 4),
                      if (vm.canMeasureCurrent && isOnline)
                        Text(
                          '${vm.currentCurrent.value!.toStringAsFixed(1)}A',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textOnSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// rolling integer moved to widgets/rolling_integer.dart
