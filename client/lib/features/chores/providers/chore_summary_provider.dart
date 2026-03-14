import 'dart:async';

import 'package:borneo_kernel_abstractions/events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/events.dart';
import '../../../core/providers.dart';
import '../models/abstract_chore.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

@immutable
class ChoreSummaryState {
  final bool isActive;
  final bool isBusy;
  final int applicableDeviceCount;
  final String? error;

  const ChoreSummaryState({this.isActive = false, this.isBusy = false, this.applicableDeviceCount = 0, this.error});

  static const _sentinel = Object();

  ChoreSummaryState copyWith({bool? isActive, bool? isBusy, int? applicableDeviceCount, Object? error = _sentinel}) {
    return ChoreSummaryState(
      isActive: isActive ?? this.isActive,
      isBusy: isBusy ?? this.isBusy,
      applicableDeviceCount: applicableDeviceCount ?? this.applicableDeviceCount,
      error: error == _sentinel ? this.error : (error as String?),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider  (family key = chore)
// ---------------------------------------------------------------------------

/// Factory that creates a [ChoreSummaryNotifier] for the given chore.
final choreSummaryProvider = NotifierProvider.family<ChoreSummaryNotifier, ChoreSummaryState, AbstractChore>(
  (arg) => ChoreSummaryNotifier(arg),
);

class ChoreSummaryNotifier extends Notifier<ChoreSummaryState> {
  final AbstractChore chore;

  ChoreSummaryNotifier(this.chore);

  @override
  ChoreSummaryState build() {
    final eventBus = ref.read(eventBusProvider);
    final deviceManager = ref.read(deviceManagerProvider);
    final subscriptions = [
      eventBus.on<ChoresChangedEvent>().listen((_) {
        unawaited(_syncActiveState());
      }),
      eventBus.on<CurrentSceneDevicesReloadedEvent>().listen((_) {
        unawaited(_syncActiveState());
      }),
      deviceManager.allDeviceEvents.on<DeviceOfflineEvent>().listen((_) {
        unawaited(_syncActiveState());
      }),
    ];
    ref.onDispose(() {
      for (final sub in subscriptions) {
        sub.cancel();
      }
    });
    return const ChoreSummaryState();
  }

  Future<void> init() async {
    await _syncActiveState();
  }

  Future<void> executeChore() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, error: null);
    final choreManager = ref.read(choreManagerProvider);
    final notification = ref.read(appNotificationServiceProvider);
    final logger = ref.read(loggerProvider);
    try {
      await choreManager.executeChore(chore.id);
      state = state.copyWith(isActive: true);
    } catch (e, st) {
      logger.e(e.toString(), error: e, stackTrace: st);
      notification.showError('Chore execution failed', body: e.toString());
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> undoChore() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, error: null);
    final choreManager = ref.read(choreManagerProvider);
    final notification = ref.read(appNotificationServiceProvider);
    final logger = ref.read(loggerProvider);
    try {
      await choreManager.undoChore(chore.id);
      state = state.copyWith(isActive: false);
    } catch (e, st) {
      logger.e(e.toString(), error: e, stackTrace: st);
      notification.showError('Undo chore failed', body: e.toString());
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> _syncActiveState() async {
    final choreManager = ref.read(choreManagerProvider);
    final deviceManager = ref.read(deviceManagerProvider);
    final logger = ref.read(loggerProvider);
    try {
      final isActive = await choreManager.hasHistoryForChore(chore.id);
      final applicableDeviceCount = chore.countApplicableDevices(deviceManager);
      state = state.copyWith(isActive: isActive, applicableDeviceCount: applicableDeviceCount);
    } catch (e, st) {
      logger.e('Failed to synchronize chore state', error: e, stackTrace: st);
    }
  }
}
