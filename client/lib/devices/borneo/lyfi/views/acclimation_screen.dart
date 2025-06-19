import 'package:borneo_app/devices/borneo/lyfi/view_models/acclimation_view_model.dart';
import 'package:borneo_app/core/services/device_manager.dart';
import 'package:borneo_app/core/services/i_app_notification_service.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:provider/provider.dart';

class AcclimationScreen extends StatelessWidget {
  final String deviceID;
  const AcclimationScreen({required this.deviceID, super.key});

  @override
  Widget build(BuildContext context) {
    final items = _buildSettingItems(context);
    final vm = AcclimationViewModel(
      deviceID: deviceID,
      deviceManager: context.read<DeviceManager>(),
      globalEventBus: context.read<EventBus>(),
    );
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text('Acclimation Mode')),
      body: FutureBuilder(
        future: vm.initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            return ChangeNotifierProvider(
              create: (cb) => vm,
              builder: (context, child) {
                return Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    ListView.separated(
                      physics: ClampingScrollPhysics(),
                      shrinkWrap: true,
                      itemBuilder: (context, index) => items[index],
                      itemCount: items.length,
                      separatorBuilder: (context, index) => SizedBox(height: 1),
                    ),
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Consumer<AcclimationViewModel>(
                        builder: (context, vm, child) => SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: vm.canSubmit ? () => onSubmit(vm, context) : null,
                            label: child!,
                            icon: const Icon(Icons.upload),
                          ),
                        ),
                        child: Text("Submit"),
                      ),
                    ),
                    Spacer(),
                  ],
                );
              },
            );
          }
        },
      ),
    );
  }

  List<Widget> _buildSettingItems(BuildContext context) {
    final tileColor = Theme.of(context).colorScheme.surfaceContainer;
    return <Widget>[
      ListTile(title: Text('SETTINGS', style: Theme.of(context).textTheme.titleSmall)),
      Consumer<AcclimationViewModel>(
        builder: (context, vm, _) => SwitchListTile(
          title: Text('Enabled'),
          value: vm.enabled,
          onChanged: !vm.isBusy.value && vm.isOnline ? vm.setEanbled : null, // TODO check power state
        ),
      ),

      Consumer<AcclimationViewModel>(
        builder: (context, vm, _) => ListTile(
          tileColor: tileColor,
          title: const Text('Start date'),
          trailing: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                vm.startTimestamp.toLocal().year < 2025 ? '-' : DateFormat.yMd().format(vm.startTimestamp.toLocal()),
              ),
              SizedBox(width: 8),
              const CupertinoListTileChevron(),
            ],
          ),
          onTap: !vm.isBusy.value && vm.isOnline
              ? () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: vm.startTimestamp.toLocal().year < 2025 ? now : vm.startTimestamp.toLocal(),
                    firstDate: DateTime(2025, 1, 1),
                    lastDate: now.add(const Duration(days: 100)),
                  );
                  if (picked != null) {
                    vm.updateStartTimestamp(picked);
                  }
                  /*
                          firstDate: now,
                          lastDate: now.add(Duration(days: vm.days.round())),
                        );
                        dlg.show
                        */
                }
              : null,
        ),
      ),
      Consumer<AcclimationViewModel>(
        builder: (context, vm, _) => ListTile(
          tileColor: tileColor,
          leading: Text("Duration"),
          title: Slider(value: vm.days, min: 5, max: 100, onChanged: vm.updateDays),
          trailing: Text(
            '${vm.days.round().toString()} days',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ),
      Consumer<AcclimationViewModel>(
        builder: (context, vm, _) => ListTile(
          tileColor: tileColor,
          leading: Text('Start percent'),
          title: Slider(value: vm.startPercent, min: 10, max: 90, onChanged: vm.updateStartPercent),
          trailing: Text(
            '${vm.startPercent.round().toString()}%',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ),
      /*
      ListTile(title: Text('STATUS', style: Theme.of(context).textTheme.titleSmall)),
      ListTile(title: Text("Elapsed time"), trailing: Text("3.3 days")),
      ListTile(title: Text("Current percent"), trailing: Text("63%")),
      */
    ];
  }

  void onSubmit(AcclimationViewModel vm, BuildContext context) {
    vm.enqueueUIJob(() async {
      await vm.submitToDevice();
      Provider.of<IAppNotificationService>(context, listen: false).showSuccess('Update acclimation settings succeed.');
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    });
  }
}
