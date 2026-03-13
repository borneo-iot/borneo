import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy;
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:borneo_app/routes/platform_page_route.dart';

import '../providers/scenes_provider.dart';
import '../../../core/providers.dart';
import '../../../core/services/scene_manager.dart';
import '../../../core/services/devices/device_manager.dart';
import 'scene_edit_screen.dart';
import '../../chores/views/chore_list.dart';
import '../models/scene_edit_arguments.dart';
import 'scene_card.dart';

class ScenesScreen extends ConsumerStatefulWidget {
  const ScenesScreen({super.key});
  @override
  ConsumerState<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends ConsumerState<ScenesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(scenesProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(scenesProvider);
    if (vm.isLoading && vm.scenes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.error != null && vm.scenes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(context.translate('Error: {errMsg}', nArgs: {'errMsg': vm.error!})),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(scenesProvider.notifier).initialize(),
              child: Text(context.translate('Retry')),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(scenesProvider.notifier).initialize(),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(context.translate('Scenes')),
            actions: [
              SizedBox(
                width: kToolbarHeight,
                child: vm.isLoading
                    ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        key: const Key('btn_add_scene'),
                        icon: const Icon(Icons.add_outlined),
                        onPressed: () => _showNewSceneScreen(context),
                      ),
              ),
            ],
          ),
          const _SceneList(),
          const ProvideChoresViewModel(child: ChoreList()),
          if (vm.error != null && vm.scenes.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                    ),
                    TextButton(
                      onPressed: () => ref.read(scenesProvider.notifier).initialize(),
                      child: Text(context.translate('Retry')),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showNewSceneScreen(BuildContext context) async {
    await Navigator.push(
      context,
      platformPageRoute(builder: (_) => const SceneEditScreen(args: SceneEditArguments(isCreation: true))),
    );
  }
}

class _SceneList extends ConsumerStatefulWidget {
  const _SceneList();
  @override
  ConsumerState<_SceneList> createState() => _SceneListState();
}

class _SceneListState extends ConsumerState<_SceneList> {
  static const _horizontalPadding = 16.0;
  static const _separatorWidth = 16.0;
  static const _peekFraction = 0.05;
  static const _cardVerticalMargin = 8.0;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected(int index, {required double viewportWidth, required double cardWidth}) {
    if (!_scrollController.hasClients) return;
    final itemWidth = cardWidth + _separatorWidth;
    final centerOffset = viewportWidth / 2 - cardWidth / 2;
    final targetOffset = _horizontalPadding + index * itemWidth - centerOffset;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scenes = ref.watch(scenesProvider.select((s) => s.scenes));
    return SliverToBoxAdapter(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = (constraints.maxWidth - (_horizontalPadding * 2)).clamp(0.0, double.infinity);
          final peekWidth = availableWidth * _peekFraction;
          final cardWidth = availableWidth <= 220.0
              ? availableWidth
              : (availableWidth - peekWidth).clamp(220.0, availableWidth).toDouble();
          final cardHeight = cardWidth * 9.0 / 16.0;
          final listHeight = cardHeight + (_cardVerticalMargin * 2);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final selectedIndex = scenes.indexWhere((s) => s.isSelected);
            if (selectedIndex != -1) {
              _scrollToSelected(selectedIndex, viewportWidth: constraints.maxWidth, cardWidth: cardWidth);
            }
          });

          return SizedBox(
            height: listHeight,
            child: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.unknown,
                },
              ),
              child: ListView.separated(
                key: const Key('scene_list'),
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                separatorBuilder: (_, _) => const SizedBox(width: _separatorWidth),
                scrollDirection: Axis.horizontal,
                itemCount: scenes.length,
                itemBuilder: (_, index) {
                  final scene = scenes[index];
                  return SizedBox(
                    width: cardWidth,
                    child: SceneCard(
                      scene,
                      onCentered: () =>
                          _scrollToSelected(index, viewportWidth: constraints.maxWidth, cardWidth: cardWidth),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Provide ScenesViewModel and dependencies at a high level
class ProvideScenesViewModel extends StatelessWidget {
  final Widget child;
  const ProvideScenesViewModel({required this.child, super.key});
  @override
  Widget build(BuildContext context) {
    final sceneManager = legacy.Provider.of<ISceneManager>(context, listen: false);
    final deviceManager = legacy.Provider.of<IDeviceManager>(context, listen: false);
    return ProviderScope(
      overrides: [
        sceneManagerProvider.overrideWithValue(sceneManager),
        deviceManagerProvider.overrideWithValue(deviceManager),
        scenesProvider.overrideWith(ScenesNotifier.new),
        scenesIsLoadingProvider.overrideWith((ref) => ref.watch(scenesProvider.select((s) => s.isLoading))),
      ],
      child: child,
    );
  }
}
