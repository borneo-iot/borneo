import '../../../shared/view_models/base_view_model.dart';

class MyViewModel extends BaseViewModel {
  MyViewModel();

  @override
  void notifyAppError(String message, {Object? error, StackTrace? stackTrace, bool allowDuplicates = false}) {}
}
