import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:logger/web.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/features/devices/widgets/dashboard_tile.dart';

import '../../view_models/lyfi_view_model.dart';
import '../settings_screen.dart';

class DashboardSettingsTile extends StatelessWidget {
  const DashboardSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Selector<LyfiViewModel, ({bool hasMismatch, bool isOnline, bool canChangeSettings})>(
      selector: (_, vm) =>
          (hasMismatch: vm.hasTimezoneMismatch, isOnline: vm.isOnline, canChangeSettings: vm.canChangeSettings),
      builder: (context, props, _) {
        final isDisabled = !props.canChangeSettings;
        final showDot = props.hasMismatch && props.isOnline;
        final Color fgColor = theme.colorScheme.onSurface;
        final double disabledAlpha = 0.38;
        final Color effectiveFgColor = isDisabled ? fgColor.withValues(alpha: disabledAlpha) : fgColor;
        final Color iconColor = theme.colorScheme.primary;
        final Color effectiveIconColor = isDisabled ? iconColor.withValues(alpha: disabledAlpha) : iconColor;
        final gt = GettextLocalizations.of(context);

        Widget tile = DashboardTile(
          disabled: isDisabled,
          onPressed: isDisabled ? null : () async => await _openSettings(context, gt),
          child: Badge(
            key: Key('settings_red_dot'),
            largeSize: 12,
            smallSize: 12,
            isLabelVisible: showDot,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.settings, size: 32, color: effectiveIconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.translate("Settings"),
                        style: theme.textTheme.titleMedium?.copyWith(color: effectiveFgColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        return tile;
      },
    );
  }

  Future<void> _openSettings(BuildContext context, GettextLocalizations gt) async {
    final lyfiVM = context.read<LyfiViewModel>();
    try {
      final vm = await lyfiVM.loadSettings(gt);
      if (context.mounted) {
        await pushScreen(
          context,
          screen: ChangeNotifierProvider.value(value: vm, child: SettingsScreen(vm)),
          withNavBar: false,
          pageTransitionAnimation: PageTransitionAnimation.platform,
        );
      }
    } catch (e, st) {
      if (context.mounted) {
        context.read<IAppNotificationService>().showError(context.translate('Error'), body: e.toString());
        context.read<Logger?>()?.e('Failed to open settings', error: e, stackTrace: st);
      }
    }
  }
}
