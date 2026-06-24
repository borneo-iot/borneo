import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy;
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

import '../../../core/providers.dart';
import '../../../core/services/scene_manager.dart';
import '../../../core/services/app_notification_service.dart';
import '../../../core/exceptions/scene_deletion_exceptions.dart';
import '../models/scene_edit_arguments.dart';
import '../providers/scene_edit_provider.dart';
import '../../../shared/widgets/confirmation_sheet.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Route-level shell.  Reads the legacy [ISceneManager] service from the
/// existing provider tree, then exposes both it and the route arguments as
/// Riverpod provider overrides so that the inner [_SceneEditBody] can be a
/// pure Riverpod consumer.
class SceneEditScreen extends StatelessWidget {
  final SceneEditArguments args;

  const SceneEditScreen({required this.args, super.key});

  @override
  Widget build(BuildContext context) {
    final sceneManager = legacy.Provider.of<ISceneManager>(context, listen: false);

    return ProviderScope(
      overrides: [
        sceneManagerProvider.overrideWithValue(sceneManager),
        sceneEditArgsProvider.overrideWithValue(args),
        sceneEditProvider.overrideWith(SceneEditNotifier.new),
      ],
      child: _SceneEditBody(args: args),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen body
// ---------------------------------------------------------------------------

class _SceneEditBody extends ConsumerStatefulWidget {
  final SceneEditArguments args;

  const _SceneEditBody({required this.args});

  @override
  ConsumerState<_SceneEditBody> createState() => _SceneEditBodyState();
}

class _SceneEditBodyState extends ConsumerState<_SceneEditBody> {
  static const _sceneImageAspectRatio = 16.0 / 9.0;
  static const _sceneImageMaxWidth = 480.0;

  final _formKey = GlobalKey<FormState>();

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isCreation = widget.args.isCreation;
    return Scaffold(
      appBar: AppBar(
        title: Text(isCreation ? context.translate('New Scene') : context.translate('Edit Scene')),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: _buildActions(context),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            _buildImageSection(context),
            const SizedBox(height: 16),
            _buildNameField(context),
            const SizedBox(height: 16),
            _buildNotesField(context),
            const SizedBox(height: 24),
            _buildSubmitButton(context),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Image section
  // ---------------------------------------------------------------------------

  Widget _buildImageSection(BuildContext context) {
    final imagePath = ref.watch(sceneEditProvider.select((s) => s.imagePath));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.translate('Scene Image'), style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _sceneImageMaxWidth),
            child: Stack(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _pickImage(Theme.of(context)),
                  child: AspectRatio(
                    aspectRatio: _sceneImageAspectRatio,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      child: imagePath != null && imagePath.isNotEmpty && File(imagePath).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(imagePath), fit: BoxFit.cover, width: double.infinity),
                            )
                          : Center(
                              child: Icon(Icons.add_a_photo_outlined, size: 40, color: Theme.of(context).hintColor),
                            ),
                    ),
                  ),
                ),
                if (imagePath != null && imagePath.isNotEmpty && File(imagePath).existsSync())
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => ref.read(sceneEditProvider.notifier).setImagePath(null),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Form fields
  // ---------------------------------------------------------------------------

  Widget _buildNameField(BuildContext context) {
    return TextFormField(
      initialValue: widget.args.model?.name ?? '',
      decoration: InputDecoration(
        labelText: context.translate('Name'),
        hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
        hintText: context.translate('Enter the required scene name'),
      ),
      key: const Key('field_scene_name'),
      validator: (value) {
        if (value?.trim().isEmpty ?? true) {
          return context.translate('Please enter the scene name');
        }
        return null;
      },
      onSaved: (value) {
        ref.read(sceneEditProvider.notifier).updateName(value ?? '');
      },
    );
  }

  Widget _buildNotesField(BuildContext context) {
    return TextFormField(
      initialValue: widget.args.model?.notes ?? '',
      maxLines: null,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
        hintText: context.translate('Enter the optional notes for this scene'),
        labelText: context.translate('Notes'),
      ),
      key: const Key('field_scene_notes'),
      onSaved: (value) {
        ref.read(sceneEditProvider.notifier).updateNotes(value ?? '');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Widget _buildSubmitButton(BuildContext context) {
    final isBusy = ref.watch(sceneEditProvider.select((s) => s.isBusy));
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const Key('btn_submit'),
        onPressed: isBusy ? null : () => _onSubmitPressed(context),
        child: isBusy
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(context.translate('Submit')),
      ),
    );
  }

  void _onSubmitPressed(BuildContext context) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();

    final navigator = Navigator.of(context);
    final notificationService = legacy.Provider.of<IAppNotificationService>(context, listen: false);
    final failureText = context.translate('Operation failed');

    _showLoadingDialog(context);

    ref
        .read(sceneEditProvider.notifier)
        .submit()
        .then((_) {
          if (navigator.mounted) {
            navigator.pop(); // dismiss loading dialog
            navigator.pop(true); // return success to caller
          }
        })
        .catchError((error) {
          if (navigator.mounted) {
            navigator.pop(); // dismiss loading dialog
            notificationService.showError(failureText, body: error.toString());
          }
        });
  }

  // ---------------------------------------------------------------------------
  // Actions / delete
  // ---------------------------------------------------------------------------

  List<Widget> _buildActions(BuildContext context) {
    final deletionAvailable = ref.watch(sceneEditProvider.select((s) => s.deletionAvailable));
    if (!deletionAvailable) return const [];
    final isBusy = ref.watch(sceneEditProvider.select((s) => s.isBusy));
    return [
      TextButton(
        key: const Key('btn_delete_scene'),
        onPressed: isBusy ? null : () => _onDeletePressed(context),
        child: Text(context.translate('Delete')),
      ),
    ];
  }

  Future<void> _onDeletePressed(BuildContext context) async {
    final notificationService = legacy.Provider.of<IAppNotificationService>(context, listen: false);
    final name = ref.read(sceneEditProvider).name;

    final confirmed = await AsyncConfirmationSheet.show(
      context,
      message: context.translate(
        'Are you sure you want to delete "{0}" scene? This action cannot be undone.',
        pArgs: [name],
      ),
    );
    if (!confirmed) return;
    if (!context.mounted) return;

    final loadingNavigator = Navigator.of(context, rootNavigator: false);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(sceneEditProvider.notifier).delete();
      if (context.mounted) {
        loadingNavigator.pop();
        if (navigator.canPop()) navigator.pop(true);
        notificationService.showSuccess(context.translate('Scene deleted'));
      }
    } on CannotDeleteLastSceneException {
      if (context.mounted) {
        loadingNavigator.pop();
        notificationService.showWarning(
          context.translate('Cannot Delete Scene'),
          body: context.translate('Cannot delete the last remaining scene.'),
        );
      }
    } on SceneContainsDevicesOrGroupsException {
      if (context.mounted) {
        loadingNavigator.pop();
        notificationService.showWarning(
          context.translate('Cannot Delete Scene'),
          body: context.translate(
            'This scene contains devices or device groups. Please remove all devices and groups from this scene before deleting it.',
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        loadingNavigator.pop();
        notificationService.showError(context.translate('Delete failed'), body: error.toString());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _pickImage(ThemeData theme) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      if (!kIsWeb && Platform.isWindows) {
        ref.read(sceneEditProvider.notifier).setImagePath(picked.path);
      } else {
        final cropped = await ImageCropper().cropImage(
          sourcePath: picked.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: context.translate('Crop Image'),
              toolbarColor: theme.colorScheme.primary,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.ratio16x9,
              lockAspectRatio: false,
              aspectRatioPresets: [
                CropAspectRatioPreset.ratio16x9,
                CropAspectRatioPreset.original,
                CropAspectRatioPreset.square,
              ],
            ),
            IOSUiSettings(
              title: 'Crop Image',
              doneButtonTitle: context.translate('Done'),
              cancelButtonTitle: context.translate('Cancel'),
              aspectRatioPresets: [
                CropAspectRatioPreset.ratio16x9,
                CropAspectRatioPreset.original,
                CropAspectRatioPreset.square,
              ],
            ),
          ],
        );
        if (cropped != null) {
          ref.read(sceneEditProvider.notifier).setImagePath(cropped.path);
        }
      }
    }
  }
}
