import 'package:borneo_app/core/services/scene_manager.dart';
import 'package:borneo_app/features/scenes/view_models/scene_edit_view_model.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../../shared/widgets/confirmation_sheet.dart';

class SceneEditScreen extends StatelessWidget {
  final SceneEditArguments args;
  final _formKey = GlobalKey<FormState>();

  SceneEditScreen({required this.args, super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<SceneEditViewModel>(
    create: createViewModel,
    builder: (context, child) => FutureBuilder(
      future: context.read<SceneEditViewModel>().initFuture,
      builder: (context, snapshot) {
        final vm = context.read<SceneEditViewModel>();
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Text(context.translate('Error: {errMsg}', nArgs: {'errMsg': snapshot.error.toString()})),
          );
        } else {
          return Scaffold(
            appBar: AppBar(
              title: Text(vm.isCreation ? context.translate('New Scene') : context.translate('Edit Scene')),
              backgroundColor: Theme.of(context).colorScheme.surface,
              actions: buildActions(context, args),
            ),
            body: buildBody(context),
          );
        }
      },
    ),
  );

  SceneEditViewModel createViewModel(BuildContext context) {
    return SceneEditViewModel(
      context.read<SceneManager>(),
      isCreation: args.isCreation,
      model: args.model,
      globalEventBus: context.read<EventBus>(),
      logger: context.read<Logger>(),
    );
  }

  List<Widget> makePropertyTiles(BuildContext context) {
    return [
      Consumer<SceneEditViewModel>(
        builder: (context, vm, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.translate('Scene Image'), style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Stack(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(source: ImageSource.gallery);
                      if (picked != null) {
                        if (!kIsWeb && Platform.isWindows) {
                          vm.setImagePath(picked.path);
                        } else {
                          final cropped = await ImageCropper().cropImage(
                            sourcePath: picked.path,
                            uiSettings: [
                              AndroidUiSettings(
                                toolbarTitle: 'Crop Image',
                                toolbarColor: Theme.of(context).colorScheme.primary,
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
                                aspectRatioPresets: [
                                  CropAspectRatioPreset.ratio16x9,
                                  CropAspectRatioPreset.original,
                                  CropAspectRatioPreset.square,
                                ],
                              ),
                            ],
                          );
                          if (cropped != null) {
                            vm.setImagePath(cropped.path);
                          }
                        }
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surfaceVariant,
                      ),
                      child: vm.imagePath != null && vm.imagePath!.isNotEmpty && File(vm.imagePath!).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(vm.imagePath!),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 120,
                              ),
                            )
                          : Center(
                              child: Icon(Icons.add_a_photo_outlined, size: 40, color: Theme.of(context).hintColor),
                            ),
                    ),
                  ),
                  // 删除图片按钮
                  if (vm.imagePath != null && vm.imagePath!.isNotEmpty && File(vm.imagePath!).existsSync())
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black45,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => vm.setImagePath(null),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: vm.name,
                decoration: InputDecoration(
                  labelText: context.translate('Name'),
                  hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
                  hintText: context.translate('Enter the required scene name'),
                ),
                validator: (value) {
                  if (value?.isEmpty ?? false) {
                    return context.translate('Please enter the scene name');
                  }
                  return null;
                },
                onSaved: (value) {
                  vm.name = value ?? '';
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                initialValue: vm.notes,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
                  hintText: context.translate('Enter the optional notes for this scene'),
                  labelText: context.translate('Notes'),
                ),
                onSaved: (value) {
                  vm.notes = value ?? '';
                },
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: vm.isBusy.value
                      ? null
                      : () async {
                          if (_formKey.currentState?.validate() ?? false) {
                            _formKey.currentState!.save();
                            await vm.submit();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          }
                        },
                  child: Text(context.translate('Submit')),
                ),
              ),
            ],
          );
        },
      ),
    ];
  }

  ListView buildList(BuildContext context) {
    final items = makePropertyTiles(context);
    return ListView.builder(
      shrinkWrap: true,
      itemBuilder: (BuildContext context, int index) => items[index],
      itemCount: items.length,
    );
  }

  Widget buildBody(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Form(key: _formKey, child: buildList(context)),
    );
  }

  List<Widget> buildActions(BuildContext context, SceneEditArguments args) {
    final vm = context.read<SceneEditViewModel>();
    return [
      if (vm.deletionAvailable)
        IconButton(
          onPressed: vm.isBusy.value
              ? null
              : () {
                  showModalBottomSheet(
                    context: context,
                    builder: (BuildContext context) {
                      return ConfirmationSheet(
                        message: context.translate(
                          'Are you sure you want to delete this device group? The devices within this group will not be deleted but will be moved to the "Ungrouped" group.',
                        ),
                        okPressed: () async {
                          await vm.delete();
                          if (context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                      );
                    },
                  );
                },
          icon: Icon(Icons.delete_outline),
        ),
    ];
  }
}
