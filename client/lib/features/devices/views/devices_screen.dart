import 'dart:io';
import 'dart:ui';

import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/features/devices/models/device_group_entity.dart';
import 'package:borneo_app/routes/app_routes.dart';
import 'package:borneo_app/features/devices/view_models/group_edit_view_model.dart';
import 'package:borneo_app/features/devices/view_models/group_view_model.dart';
import 'package:borneo_app/features/devices/views/device_list_tile.dart';
import 'package:borneo_app/features/devices/view_models/grouped_devices_view_model.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'group_edit_screen.dart';

enum PlusMenuIndexes { addGroup, addDevice }

class InGroupDeviceListView extends StatelessWidget {
  const InGroupDeviceListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<GroupViewModel, List<AbstractDeviceSummaryViewModel>>(
      selector: (_, gvm) => gvm.devices,
      builder: (context, devices, child) {
        var index = 0;
        final List<Widget> deviceWidgets = <Widget>[];
        for (var dvm in devices) {
          deviceWidgets.add(ChangeNotifierProvider.value(value: dvm, child: DeviceTile(index == devices.length - 1)));
          if (index < devices.length - 1) {
            deviceWidgets.add(
              Container(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Row(
                  children: [
                    const SizedBox(width: 72), // 48 icon + 16 ListTile padding + 8
                    Expanded(child: Divider(height: 1, thickness: 1, color: Theme.of(context).colorScheme.surface)),
                  ],
                ),
              ),
            );
          }
          index++;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: deviceWidgets);
      },
    );
  }
}

class NoDataHintView extends StatelessWidget {
  const NoDataHintView({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
        child: Center(
          child: Column(
            children: [
              const Spacer(),
              Text(
                context.translate('There are no devices or device groups in the current scene.'),
                style: DefaultTextStyle.of(context).style.copyWith(color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: Icon(Icons.add_outlined),
                label: Text(context.translate("Add new devices")),
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.kDeviceDiscovery);
                },
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  static const _smallShadow = Shadow(offset: Offset(1.0, 1.0), blurRadius: 2.0, color: Color.fromARGB(128, 0, 0, 0));

  Future<void> _showDiscoveryPage(BuildContext context) async {
    await Navigator.of(context).pushNamed(AppRoutes.kDeviceDiscovery);
  }

  Future<void> _showNewGroupScreen(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupEditScreen(),
        settings: RouteSettings(arguments: GroupEditArguments(isCreation: true)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<GroupedDevicesViewModel>();
    return FutureBuilder(
      future: vm.initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(context.translate('Error: {errMsg}', nArgs: {'errMsg': snapshot.error.toString()})),
            ),
          );
        } else {
          return Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                _buildAppBar(context),
                Selector<GroupedDevicesViewModel, List<GroupViewModel>>(
                  selector: (_, vm) => vm.groups,
                  shouldRebuild: (previous, current) =>
                      previous.length != current.length ||
                      previous.any(
                        (preGroup) => current.any(
                          (curGroup) =>
                              preGroup.id == curGroup.id &&
                              (preGroup.name != curGroup.name || preGroup.isEmpty != curGroup.isEmpty),
                        ),
                      ),
                  builder: (context, groups, child) {
                    final groupedDevicesVM = context.read<GroupedDevicesViewModel>();
                    return groupedDevicesVM.isEmpty
                        ? NoDataHintView()
                        : SliverList.builder(
                            itemCount: groups.length,
                            itemBuilder: (context, index) {
                              final gvm = groups[index];
                              return _buildGroupSection(context, gvm);
                            },
                          );
                  },
                ),
              ],
            ),
          );
        }
      },
    );
  }

  PopupMenuButton _buildAddButtons(BuildContext context) {
    return PopupMenuButton<PlusMenuIndexes>(
      icon: Icon(Icons.add_outlined, color: Colors.white, shadows: [_smallShadow]),
      onSelected: (value) {
        switch (value) {
          case PlusMenuIndexes.addDevice:
            {
              _showDiscoveryPage(context);
              break;
            }
          case PlusMenuIndexes.addGroup:
            {
              _showNewGroupScreen(context);
              break;
            }
        }
        // Handle menu item selection
      },
      itemBuilder: (BuildContext context) {
        return <PopupMenuEntry<PlusMenuIndexes>>[
          PopupMenuItem<PlusMenuIndexes>(
            value: PlusMenuIndexes.addDevice,
            child: Text(context.translate('Add New Devices')),
          ),
          PopupMenuItem<PlusMenuIndexes>(
            value: PlusMenuIndexes.addGroup,
            child: Text(context.translate('Add Devices Group')),
          ),
        ];
      },
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundColor: Colors.white,
      title: Text(
        context.translate(
          'Devices in {currentScene}',
          nArgs: {'currentScene': context.read<GroupedDevicesViewModel>().currentScene.name},
        ),
        style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
          color: Colors.white,
          shadows: [const Shadow(blurRadius: 4.0, color: Colors.black, offset: Offset(2.0, 2.0))],
        ),
      ),
      actions: [_buildAddButtons(context)],
      //expandedHeight: MediaQuery.of(context).size.height / 8.0,
      flexibleSpace: FlexibleSpaceBar(
        expandedTitleScale: 1.0,
        background: ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.5),
                Colors.black.withValues(alpha: 0.7),
              ],
              stops: [0.0, 0.6, 0.8, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
            child: context.read<GroupedDevicesViewModel>().currentScene.imagePath != null
                ? Image.file(
                    File(context.read<GroupedDevicesViewModel>().currentScene.imagePath!),
                    fit: BoxFit.cover,
                    height: double.infinity,
                    width: double.infinity,
                    alignment: Alignment.center,
                  )
                : Image.asset(
                    'assets/images/scenes/scene-default-noimage.jpg',
                    fit: BoxFit.cover,
                    height: double.infinity,
                    width: double.infinity,
                    alignment: Alignment.center,
                  ),
          ),
        ),
        stretchModes: [StretchMode.zoomBackground],
      ),
      pinned: true,
    );
  }

  Widget _buildGroupSection(BuildContext context, GroupViewModel g) {
    return ChangeNotifierProvider<GroupViewModel>.value(
      value: g,
      builder: (context, child) => Selector<GroupViewModel, ({String name, bool isEmpty, bool isDummy, bool isBusy})>(
        selector: (_, gvm) => (name: gvm.name, isEmpty: gvm.isEmpty, isDummy: gvm.isDummy, isBusy: gvm.isBusy.value),
        builder: (context, groupData, child) {
          if (groupData.isDummy && groupData.isEmpty) {
            return SizedBox(height: 0);
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  height: 32,
                  child: Row(
                    children: [
                      Text(groupData.name, textAlign: TextAlign.start, style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (!groupData.isDummy)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 24),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                          constraints: null,
                          onPressed: groupData.isDummy || groupData.isBusy
                              ? null
                              : () => _showEditGroupPage(context, g.model),
                        ),
                    ],
                  ),
                ),
                const InGroupDeviceListView(),
              ],
            );
          }
        },
      ),
    );
  }

  void _showEditGroupPage(BuildContext context, DeviceGroupEntity group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupEditScreen(),
        settings: RouteSettings(arguments: GroupEditArguments(isCreation: false, model: group)),
      ),
    );
  }
}
