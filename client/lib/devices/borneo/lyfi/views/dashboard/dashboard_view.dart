import 'package:borneo_app/devices/borneo/lyfi/views/dashboard/dashboard_settings_tile.dart';
import 'package:borneo_app/shared/widgets/screen_top_rounded_container.dart';
import 'package:flutter/material.dart';

import 'dashboard_acclimation_tile.dart';
import 'dashboard_chart.dart';
import 'dashboard_power_switch_tile.dart';
import 'dashboard_temporary_tile.dart';
import 'dashboard_temperature_tile.dart';
import 'dashboard_power_tile.dart';
import 'dashboard_dimming_tile.dart';
import 'dashboard_moon_tile.dart';

class _DashboardControlPanel extends StatelessWidget {
  const _DashboardControlPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ScreenTopRoundedContainer(
      color: colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: const SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(flex: 1, child: DashboardPowerSwitchTile()),
                SizedBox(width: 16),
                Expanded(flex: 1, child: DashboardTemporaryTile()),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: DashboardPowerTile()),
                SizedBox(width: 16),
                Expanded(child: DashboardTemperatureTile()),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(flex: 1, child: DashboardMoonTile()),
                SizedBox(width: 16),
                Expanded(flex: 1, child: DashboardAcclimationTile()),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(flex: 1, child: DashboardDimmingTile()),
                SizedBox(width: 16),
                Expanded(flex: 1, child: DashboardSettingsTile()),
              ],
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chart
          Expanded(
            child: RepaintBoundary(
              child: Container(
                color: theme.scaffoldBackgroundColor,
                margin: const EdgeInsets.all(0),
                child: const ClipRect(child: DashboardChart()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const RepaintBoundary(child: _DashboardControlPanel()),
        ],
      ),
    );
  }
}
