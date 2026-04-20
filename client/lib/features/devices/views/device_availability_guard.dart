import 'package:borneo_app/features/devices/view_models/base_device_view_model.dart';
import 'package:flutter/material.dart';

class DeviceAvailabilityGuard<TDeviceViewModel extends BaseDeviceViewModel> extends StatefulWidget {
  final TDeviceViewModel viewModel;
  final Widget child;

  const DeviceAvailabilityGuard({required this.viewModel, required this.child, super.key});

  @override
  State<DeviceAvailabilityGuard<TDeviceViewModel>> createState() => _DeviceAvailabilityGuardState<TDeviceViewModel>();
}

class _DeviceAvailabilityGuardState<TDeviceViewModel extends BaseDeviceViewModel>
    extends State<DeviceAvailabilityGuard<TDeviceViewModel>> {
  bool _didHandleUnavailable = false;

  void _dismissGuardedRoute() {
    final route = ModalRoute.of(context);
    final navigator = Navigator.maybeOf(context);
    if (route == null || navigator == null) {
      return;
    }

    // Remove the route that owns this guard instead of popping the current
    // top-most route. This avoids hidden device pages surviving underneath a
    // settings/details overlay and later surfacing as a blank screen.
    route.navigator?.removeRoute(route);
  }

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
    _onViewModelChanged();
  }

  @override
  void didUpdateWidget(covariant DeviceAvailabilityGuard<TDeviceViewModel> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.viewModel, widget.viewModel)) {
      return;
    }
    oldWidget.viewModel.removeListener(_onViewModelChanged);
    widget.viewModel.addListener(_onViewModelChanged);
    _didHandleUnavailable = false;
    _onViewModelChanged();
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted || _didHandleUnavailable || widget.viewModel.isAvailable) {
      return;
    }

    _didHandleUnavailable = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      _dismissGuardedRoute();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
