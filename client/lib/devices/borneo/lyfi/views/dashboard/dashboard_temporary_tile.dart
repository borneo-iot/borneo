import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/features/devices/widgets/dashboard_tile.dart';

import '../../view_models/lyfi_view_model.dart';
import 'package:borneo_kernel/drivers/borneo/lyfi/models.dart';
import '../disco_page.dart';

class DashboardTemporaryTile extends StatelessWidget {
  const DashboardTemporaryTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<LyfiViewModel, ({LyfiState? state, bool canSwitch, Duration total, Duration remain})>(
      selector: (context, vm) => (
        state: vm.state,
        canSwitch: vm.canSwitchTemporaryState,
        total: vm.temporaryDuration,
        remain: vm.temporaryRemaining,
      ),
      builder: (context, props, _) {
        final theme = Theme.of(context);
        final isActive = props.state == LyfiState.temporary;
        final remainSeconds = props.remain.inSeconds;
        String remainText = '';
        if (isActive && props.total.inSeconds > 0) {
          final min = (remainSeconds ~/ 60).toString().padLeft(2, '0');
          final sec = (remainSeconds % 60).toString().padLeft(2, '0');
          remainText = '$min:$sec';
        }
        final Color bgColor = isActive ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest;
        final Color fgColor = isActive ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface;
        final double disabledAlpha = 0.38;
        final Color effectiveFgColor = !props.canSwitch ? fgColor.withValues(alpha: disabledAlpha) : fgColor;
        final Color iconColor = isActive ? theme.colorScheme.onPrimary : theme.colorScheme.primary;
        final Color effectiveIconColor = !props.canSwitch ? iconColor.withValues(alpha: disabledAlpha) : iconColor;
        return DashboardTile(
          backgroundColor: bgColor,
          disabled: !props.canSwitch,
          onPressed: props.canSwitch ? () => _switchTemporary(context) : null,
          onLongPressed: props.canSwitch ? () => _gotoDiscoScreen(context) : null,
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
                              padding: const EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeAlign: 1,
                                strokeWidth: 2,
                                value: props.total.inSeconds > 0 ? props.remain.inSeconds / props.total.inSeconds : 0.0,
                                backgroundColor: theme.colorScheme.shadow,
                                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.onPrimaryContainer),
                              ),
                            ),
                          )
                        : Container(
                            key: const ValueKey('inactive'),
                            alignment: Alignment.center,
                            child: Icon(Icons.flashlight_on, size: 32, color: effectiveIconColor),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.translate("Temporary"),
                          style: theme.textTheme.titleSmall?.copyWith(color: effectiveFgColor),
                        ),
                        if (isActive && remainText.isNotEmpty)
                          Text(
                            remainText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: effectiveFgColor,
                              fontFeatures: const [FontFeature.tabularFigures()],
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
                    Icons.flashlight_on,
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

  Future<void> _gotoDiscoScreen(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final vm = context.read<LyfiViewModel>();
    if (!vm.canSwitchDiscoState) {
      return;
    }
    vm.switchDiscoState();
    if (context.mounted) {
      await pushScreen(
        context,
        screen: ChangeNotifierProvider.value(value: vm, child: const DiscoPage()),
        withNavBar: false,
        pageTransitionAnimation: PageTransitionAnimation.platform,
      );
    }
  }

  void _switchTemporary(BuildContext context) {
    context.read<LyfiViewModel>().switchTemporaryState();
  }
}
