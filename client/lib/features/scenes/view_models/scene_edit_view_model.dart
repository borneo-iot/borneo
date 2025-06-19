import 'package:borneo_app/core/models/scene_entity.dart';
import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/shared/view_models/abstract_screen_view_model.dart';

final class SceneEditArguments {
  final bool isCreation;
  final SceneEntity? model;

  const SceneEditArguments({required this.isCreation, this.model});
}

class SceneEditViewModel extends AbstractScreenViewModel {
  final SceneManager _sceneManager;
  final bool isCreation;
  late final String? id;
  late String name;
  late String notes;
  String? imagePath;

  final bool _deletionAvailable;
  bool get deletionAvailable => _deletionAvailable;

  SceneEditViewModel(
    this._sceneManager, {
    required super.globalEventBus,
    required this.isCreation,
    SceneEntity? model,
    super.logger,
  }) : _deletionAvailable = !isCreation {
    if (isCreation) {
      name = '';
      notes = '';
      imagePath = null;
    } else {
      name = model!.name;
      notes = model.notes;
      imagePath = model.imagePath;
    }
    id = model?.id;
  }

  // 新增：设置图片路径
  void setImagePath(String? path) {
    imagePath = path;
    notifyListeners();
  }

  @override
  Future<void> onInitialize() async {
    // nothing to do
  }
  Future<void> submit() async {
    assert(!isBusy.value && isInitialized);

    setBusy(true);
    try {
      if (isCreation) {
        await _sceneManager.create(name: name, notes: notes, imagePath: imagePath);
      } else {
        await _sceneManager.update(id: id!, name: name, notes: notes, imagePath: imagePath);
      }
    } catch (e, stackTrace) {
      notifyAppError('Failed to update scene `$name`', error: e, stackTrace: stackTrace);
    } finally {
      setBusy(false);
    }
  }

  Future<void> delete() async {
    assert(!isCreation && !isBusy.value && isInitialized);
    setBusy(true);
    try {
      await _sceneManager.delete(id!);
    } catch (e, stackTrace) {
      notifyAppError('Failed to delete scene `$name`', error: e, stackTrace: stackTrace);
    } finally {
      setBusy(false);
    }
  }
}
