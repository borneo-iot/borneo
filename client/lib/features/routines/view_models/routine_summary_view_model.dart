import 'package:borneo_app/features/routines/models/abstract_routine.dart';
import 'package:borneo_app/core/services/i_app_notification_service.dart';
import 'package:borneo_app/core/services/routine_manager.dart';
import 'package:borneo_app/shared/view_models/base_view_model.dart';

class RoutineSummaryViewModel extends BaseViewModel {
  String get name => _model.name;

  bool _isActive = false;
  bool get isActive => _isActive;
  String get iconAssetPath => _model.iconAssetPath;

  final AbstractRoutine _model;
  final IAppNotificationService _notification;
  final RoutineManager _routineManager;
  RoutineSummaryViewModel(this._model, this._routineManager, this._notification, {super.logger});
  Future<void> executeRoutine() async {
    if (super.isBusy.value) return;
    isBusy.value = true;
    notifyListeners();
    try {
      await _routineManager.executeRoutine(_model.id);
      _isActive = true;
    } catch (e, stackTrace) {
      super.logger?.e(e.toString(), error: e, stackTrace: stackTrace);
      _notification.showError('Routine execution failed', body: e.toString());
    } finally {
      isBusy.value = false;
      notifyListeners();
    }
  }

  Future<void> undoRoutine() async {
    if (isBusy.value) {
      return;
    }
    isBusy.value = true;
    notifyListeners();
    try {
      await _routineManager.undoRoutine(_model.id);
      _isActive = false;
    } catch (e, stackTrace) {
      super.logger?.e(e.toString(), error: e, stackTrace: stackTrace);
      _notification.showError('Undo routine failed', body: e.toString());
    } finally {
      isBusy.value = false;
      notifyListeners();
    }
  }

  @override
  void notifyAppError(String message, {Object? error, StackTrace? stackTrace}) {
    _notification.showError(message, body: error?.toString());
  }
}
