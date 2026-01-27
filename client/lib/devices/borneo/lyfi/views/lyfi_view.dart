import 'package:borneo_app/core/services/local_service.dart';
import 'package:borneo_app/features/devices/models/device_entity.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/gettext_localizations.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/devices/borneo/lyfi/views/dashboard/dashboard_view.dart';
import 'package:borneo_app/core/services/devices/device_manager.dart';

import '../view_models/lyfi_view_model.dart';
import 'widgets/lyfi_header.dart';

class CircleButton extends StatelessWidget {
  final String text;
  final Widget icon;
  final Color? color;
  final Color? backgroundColor;
  final VoidCallback? onPressed;

  const CircleButton({
    super.key,
    required this.text,
    required this.icon,
    this.color,
    this.backgroundColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(0),
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10.0), color: backgroundColor),
              child: IconButton(
                onPressed: onPressed,
                padding: EdgeInsets.all(8),
                icon: icon,
                color: color,
                style: ButtonStyle(
                  shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      side: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1.0),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 2),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class HeroVerticalDivider extends StatelessWidget {
  final double width;
  final Color color;

  const HeroVerticalDivider({super.key, this.width = 8, this.color = Colors.grey});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: VerticalDivider(color: color, thickness: 1),
    );
  }
}

/*
class HeroProgressIndicator extends StatelessWidget {
  final Widget? label;
  final Widget? center;
  final double radius;
  final double percent;
  final LinearGradient? linearGradient;
  final Widget? icon;

  const HeroProgressIndicator({
    super.key,
    this.radius = 24,
    this.percent = 0,
    this.center,
    this.label,
    this.linearGradient,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircularPercentIndicator(
          animateFromLastPercent: true,
          animation: true,
          radius: radius,
          arcType: ArcType.FULL,
          lineWidth: 1.5,
          percent: percent,
          center: center,
          footer: label,
          progressColor: Theme.of(context).colorScheme.primary,
          linearGradient: linearGradient,
          arcBackgroundColor: Theme.of(context).colorScheme.outlineVariant,
        ),
        if (icon != null) Positioned.fill(child: Align(alignment: Alignment.bottomCenter, child: icon!)),
      ],
    );
  }
}
*/

class _LyfiDeviceDetailsScreen extends StatelessWidget {
  const _LyfiDeviceDetailsScreen();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        final vm = context.read<LyfiViewModel>();
        if (!vm.isLocked && !vm.isSuspectedOffline) {
          vm.toggleLock(true);
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            LyfiAppBar(onBack: () => goBack(context)),
            const LyfiBusyIndicatorSliver(),
            const LyfiStatusBannersSliver(),
          ],
          body: const SafeArea(top: false, child: DashboardView(key: ValueKey('dashboard'))),
        ),
      ),
    );
  }

  void goBack(BuildContext context) async {
    final vm = context.read<LyfiViewModel>();
    if (vm.isLocked) {
      Navigator.of(context).pop();
    } else {
      if (!vm.isSuspectedOffline) {
        vm.toggleLock(true);
      }
    }
  }
}

class LyfiView extends StatelessWidget {
  const LyfiView({super.key});
  @override
  Widget build(BuildContext context) {
    final device = ModalRoute.of(context)!.settings.arguments as DeviceEntity;
    return ChangeNotifierProvider(
      create: (cb) => LyfiViewModel(
        deviceID: device.id,
        deviceManager: cb.read<IDeviceManager>(),
        globalEventBus: cb.read<EventBus>(),
        notification: cb.read<IAppNotificationService>(),
        localeService: cb.read<ILocaleService>(),
        logger: cb.read<Logger>(),
        gt: cb.read<GettextLocalizations>(),
      ),
      builder: (context, child) {
        final vm = context.read<LyfiViewModel>();
        return FutureBuilder(
          future: vm.initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                appBar: AppBar(backgroundColor: Theme.of(context).scaffoldBackgroundColor, title: Text(device.name)),
                body: Column(
                  children: [
                    SizedBox(
                      height: 1,
                      width: double.infinity,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onPrimary),
                      ),
                    ),
                    Expanded(child: Container()),
                  ],
                ),
              );
            } else if (snapshot.hasError) {
              return Scaffold(body: Center(child: Text('Error: [${snapshot.error}]')));
            } else {
              return _LyfiDeviceDetailsScreen();
            }
          },
        );
      },
    );
  }
}
