import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:borneo_app/routes/platform_page_route.dart';

import '../view_models/scenes_view_model.dart';
import '../providers/scenes_provider.dart';
import 'scene_edit_screen.dart';
import '../models/scene_edit_arguments.dart';

class SceneCard extends ConsumerWidget {
  final SceneSummaryModel scene;
  final VoidCallback? onCentered;
  static const _smallShadow = Shadow(offset: Offset(1.0, 1.0), blurRadius: 2.0, color: Color.fromARGB(128, 0, 0, 0));
  static const _unselectedImageMatrix = <double>[
    0.48,
    0.35,
    0.07,
    0,
    0,
    0.18,
    0.65,
    0.07,
    0,
    0,
    0.18,
    0.35,
    0.37,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  const SceneCard(this.scene, {super.key, this.onCentered});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isBusy = ref.watch(scenesProvider.select((s) => s.isLoading));
    final showSpinner = ref.watch(scenesProvider.select((s) => s.switchingSceneId)) == scene.id && isBusy;
    return Card(
      key: Key('scene_card_${scene.name}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      borderOnForeground: true,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: AspectRatio(
        aspectRatio: 16.0 / 9.0,
        child: Material(
          color: scene.isSelected ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16.0),
          child: InkWell(
            onTap: (!scene.isSelected && !isBusy)
                ? () async {
                    onCentered?.call();
                    await ref.read(scenesProvider.notifier).switchCurrentScene(scene.id);
                  }
                : null,
            child: _buildContent(context, showSpinner, isBusy),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool showSpinner, bool interactionsDisabled) {
    Widget editWidget;
    if (showSpinner) {
      editWidget = SizedBox(
        key: Key('scene_spinner_${scene.id}'),
        width: 44,
        height: 44,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else {
      editWidget = _buildEditButton(context, disabled: interactionsDisabled);
    }

    if (scene.isSelected) {
      return Stack(
        alignment: Alignment.topRight,
        children: [
          _buildSceneImage(context),
          _buildSceneInfo(context),
          Positioned(top: 0.0, right: 0.0, child: editWidget),
        ],
      );
    }
    return Stack(
      alignment: Alignment.topRight,
      children: [
        ColorFiltered(colorFilter: const ColorFilter.matrix(_unselectedImageMatrix), child: _buildSceneImage(context)),
        Positioned.fill(child: _buildUnselectedOverlay()),
        _buildSceneInfo(context),
        Positioned(top: 0.0, right: 0.0, child: editWidget),
      ],
    );
  }

  Widget _buildEditButton(BuildContext context, {bool disabled = false}) {
    // Corner overlay matching card's 16px radius, flush to edges
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(16),
        topLeft: Radius.circular(0),
        bottomLeft: Radius.circular(16), // Keep symmetry if height shrinks; adjust if undesired
        bottomRight: Radius.circular(0),
      ),
      child: Material(
        color: Colors.black.withValues(alpha: 0.32),
        child: InkWell(
          onTap: disabled ? null : () => _showEditSceneScreen(context),
          key: Key('btn_edit_scene_${scene.name}'),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                Icons.edit_outlined,
                color: Colors.white,
                size: 20,
                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 2, color: Color.fromARGB(160, 0, 0, 0))],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSceneImage(BuildContext context) {
    if (scene.scene.imagePath == null) {
      return Image.asset('assets/images/scenes/scene-default-noimage.jpg', fit: BoxFit.cover, width: double.infinity);
    }
    if (scene.scene.imagePath != null) {
      return Image.file(File(scene.scene.imagePath!), fit: BoxFit.cover, width: double.infinity);
    }
    return const SizedBox.shrink();
  }

  Widget _buildUnselectedOverlay() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withAlpha(28), Colors.black.withAlpha(58), Colors.black.withAlpha(92)],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  Widget _buildSceneInfo(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: 16,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scene.name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  shadows: [Shadow(offset: const Offset(2.0, 2.0), blurRadius: 4.0, color: Colors.black.withAlpha(97))],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    context.translate('{0} devices', pArgs: ['${scene.totalDeviceCount}']),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white, shadows: const [_smallShadow]),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.circle, size: 4, color: Colors.white, shadows: [_smallShadow]),
                  const SizedBox(width: 8),
                  Text(
                    context.translate('{0} active', pArgs: ['${scene.activeDeviceCount}']),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white, shadows: const [_smallShadow]),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showEditSceneScreen(BuildContext context) async {
    await Navigator.push(
      context,
      platformPageRoute(
        builder: (_) => SceneEditScreen(args: SceneEditArguments(isCreation: false, model: scene.scene)),
      ),
    );
  }
}
