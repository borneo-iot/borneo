import 'dart:io';
import 'dart:ui';

import 'package:borneo_app/features/devices/providers/group_edit_provider.dart';
import 'package:borneo_app/features/devices/providers/new_device_candidates_store.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/features/devices/models/device_group_entity.dart';
import 'package:borneo_app/features/devices/view_models/group_view_model.dart';
import 'package:borneo_app/features/devices/views/device_card.dart';
import 'package:borneo_app/features/devices/view_models/grouped_devices_view_model.dart';
import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_app/devices/view_models/abstract_device_summary_view_model.dart';
import 'package:borneo_app/features/devices/widgets/empty_groups_widget.dart';
import 'package:borneo_app/features/devices/views/device_discovery_screen.dart';
import 'group_edit_screen.dart';

enum PlusMenuIndexes { addGroup, addDevice }

/// A small badge showing the number of new device candidates.
///
/// This is used both as the icon of the "add" button on the app bar and
/// appended to the "Add New Devices" popup menu item.
///
/// The [child] widget, if provided, is wrapped by the `Badge` so it can be
/// reused for the icon; when omitted an empty box is used, which is handy for
/// the menu item where only the count bubble is desired.
class _NewDevicesBadge extends StatelessWidget {
  final Widget? child;

  const _NewDevicesBadge({this.child});

  @override
  Widget build(BuildContext context) {
    return Selector<NewDeviceCandidatesStore, int>(
      selector: (_, store) => store.count,
      builder: (_, count, _) => Badge(
        isLabelVisible: count > 0,
        label: Text(count > 9 ? '9+' : '$count'),
        backgroundColor: Colors.green[400],
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

class NoDataHintView extends StatelessWidget {
  const NoDataHintView({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: EmptyGroupsWidget(
        onCreateGroup: () async {
          await pushScreen(
            context,
            screen: const DeviceDiscoveryScreen(),
            withNavBar: false,
            pageTransitionAnimation: PageTransitionAnimation.platform,
          );
          // Refresh after adding devices
          if (context.mounted) {
            context.read<GroupedDevicesViewModel>().refresh();
          }
        },
      ),
    );
  }
}

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  static const _smallShadow = Shadow(offset: Offset(1.0, 1.0), blurRadius: 2.0, color: Color.fromARGB(128, 0, 0, 0));

  Future<void> _showDiscoveryPage(BuildContext context) async {
    await pushScreen(
      context,
      screen: const DeviceDiscoveryScreen(),
      withNavBar: false,
      pageTransitionAnimation: PageTransitionAnimation.platform,
    );
  }

  Future<void> _showNewGroupScreen(BuildContext context) async {
    final result = await pushScreen(
      context,
      screen: const GroupEditScreen(args: GroupEditArguments(isCreation: true)),
      withNavBar: false,
      pageTransitionAnimation: PageTransitionAnimation.platform,
    );

    // Refresh if group was created
    if (result == true && context.mounted) {
      context.read<GroupedDevicesViewModel>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<GroupedDevicesViewModel>();
    return FutureBuilder(
      future: vm.initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Text(context.translate('Error: {errMsg}', nArgs: {'errMsg': snapshot.error.toString()})),
          );
        } else {
          return Scaffold(
            appBar: _buildAppBar(context),
            body: RefreshIndicator(
              onRefresh: () => context.read<GroupedDevicesViewModel>().refreshDiscovery(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: <Widget>[
                  Selector<GroupedDevicesViewModel, List<GroupSnapshot>>(
                    selector: (_, vm) => vm.groups
                        .map(
                          (g) => GroupSnapshot(
                            id: g.id,
                            name: g.name,
                            deviceCount: g.devices.length,
                            lastModified: g.lastModified,
                            isDummy: g.isDummy,
                          ),
                        )
                        .toList(),
                    shouldRebuild: (previous, current) {
                      if (previous.length != current.length) return true;
                      for (var i = 0; i < previous.length; i++) {
                        if (previous[i] != current[i]) return true;
                      }
                      return false;
                    },
                    builder: (context, groupSnapshots, child) {
                      final groupedDevicesVM = context.read<GroupedDevicesViewModel>();
                      if (groupedDevicesVM.isLoading) {
                        return const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return groupedDevicesVM.hasNoDevices
                          ? const NoDataHintView()
                          : SliverList.builder(
                              itemCount: groupSnapshots.length,
                              itemBuilder: (context, index) {
                                final snapshot = groupSnapshots[index];
                                final gvm = groupedDevicesVM.groups.firstWhere((g) => g.id == snapshot.id);
                                return KeyedSubtree(
                                  key: ValueKey(snapshot.id),
                                  child: _buildGroupSection(context, gvm),
                                );
                              },
                            );
                    },
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  PopupMenuButton _buildAddButtons(BuildContext context) {
    return PopupMenuButton<PlusMenuIndexes>(
      icon: const _NewDevicesBadge(
        child: Icon(Icons.add_outlined, color: Colors.white, shadows: [_smallShadow]),
      ),
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
      },
      itemBuilder: (BuildContext context) {
        return <PopupMenuEntry<PlusMenuIndexes>>[
          PopupMenuItem<PlusMenuIndexes>(
            value: PlusMenuIndexes.addDevice,
            child: _NewDevicesBadge(child: Text(context.translate('Add New Devices'))),
          ),
          PopupMenuItem<PlusMenuIndexes>(
            key: const Key('menu_item_add_group'),
            value: PlusMenuIndexes.addGroup,
            child: Text(context.translate('Add Devices Group')),
          ),
        ];
      },
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final scene = context.select<GroupedDevicesViewModel, SceneEntity>((vm) => vm.currentScene);

    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundColor: Colors.white,
      title: Text(
        context.translate('Devices in {currentScene}', nArgs: {'currentScene': scene.name}),
        style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
          color: Colors.white,
          shadows: [const Shadow(blurRadius: 4.0, color: Colors.black, offset: Offset(2.0, 2.0))],
        ),
      ),
      actions: [_buildAddButtons(context)],
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
            child: scene.imagePath != null
                ? Image.file(
                    File(scene.imagePath!),
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
    );
  }

  Widget _buildGroupSection(BuildContext context, GroupViewModel g) {
    return ChangeNotifierProvider<GroupViewModel>.value(
      value: g,
      builder: (context, child) =>
          Selector<GroupViewModel, ({String name, bool isEmpty, bool isDummy, bool isBusy, int deviceCount})>(
            selector: (_, gvm) => (
              name: gvm.name,
              isEmpty: gvm.isEmpty,
              isDummy: gvm.isDummy,
              isBusy: gvm.isBusy,
              deviceCount: gvm.devices.length,
            ),
            builder: (context, groupData, child) {
              if (groupData.isDummy && groupData.isEmpty) {
                return const SizedBox(height: 0);
              }
              final crossAxisCount = (MediaQuery.sizeOf(context).width / 180).clamp(2, 4).toInt();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Group header
                  Container(
                    margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    height: 48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          groupData.name,
                          textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        // separator line filling the space before edit button
                        const SizedBox(width: 8),
                        Expanded(
                          child: Divider(
                            height: 8,
                            thickness: 8,
                            color: Theme.of(context).colorScheme.surfaceContainer,
                            radius: const BorderRadius.all(Radius.circular(2.5)),
                          ),
                        ),
                        if (!groupData.isDummy) const SizedBox(width: 8),
                        if (!groupData.isDummy)
                          IconButton(
                            key: Key('btn_edit_group_${groupData.name}'),
                            icon: Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.primary),
                            constraints: null,
                            onPressed: groupData.isDummy || groupData.isBusy
                                ? null
                                : () => _showEditGroupPage(context, g.model),
                          ),
                      ],
                    ),
                  ),
                  // Device card grid
                  GridView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: groupData.deviceCount,
                    itemBuilder: (context, index) {
                      // Use a nullable selector so that if GroupViewModel
                      // notifies listeners with fewer devices than the
                      // snapshot-based itemCount (e.g. during _clearAllItems),
                      // we return null instead of throwing a RangeError.
                      // Flutter will remove the item from the tree on the next
                      // frame once the outer Selector rebuilds with deviceCount=0.
                      return Selector<GroupViewModel, AbstractDeviceSummaryViewModel?>(
                        selector: (_, gvm) => index < gvm.devices.length ? gvm.devices[index] : null,
                        shouldRebuild: (previous, current) => previous != current,
                        builder: (context, deviceVM, _) {
                          if (deviceVM == null) {
                            return const SizedBox.shrink();
                          }
                          return ChangeNotifierProvider.value(
                            key: ValueKey(deviceVM.deviceEntity.id),
                            value: deviceVM,
                            child: const DeviceCard(),
                          );
                        },
                      );
                    },
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showEditGroupPage(BuildContext context, DeviceGroupEntity group) async {
    final result = await pushScreen(
      context,
      screen: GroupEditScreen(args: GroupEditArguments(isCreation: false, model: group)),
      withNavBar: false,
      pageTransitionAnimation: PageTransitionAnimation.platform,
    );

    // Refresh if group was deleted or updated
    if (result == true && context.mounted) {
      context.read<GroupedDevicesViewModel>().refresh();
    }
  }
}
