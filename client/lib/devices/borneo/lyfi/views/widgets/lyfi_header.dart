import 'package:borneo_common/io/net/rssi.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../view_models/lyfi_view_model.dart';

/// Sliver AppBar for Lyfi device details, to be shared by Dashboard and Dimming screens.
class LyfiAppBar extends StatelessWidget {
  final VoidCallback? onBack;
  const LyfiAppBar({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: false,
      floating: false,
      snap: false,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: Selector<LyfiViewModel, ({String name, String model})>(
        selector: (_, vm) => (name: vm.name, model: vm.deviceEntity.model),
        builder: (context, data, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.name, style: Theme.of(context).textTheme.titleMedium),
            Text(data.model, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      leading: Selector<LyfiViewModel, bool>(
        selector: (context, vm) => vm.isBusy,
        builder: (context, isBusy, child) =>
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: isBusy ? null : onBack),
      ),
      actions: [
        Selector<LyfiViewModel, bool>(
          selector: (_, vm) => vm.cloudActivated,
          builder: (context, cloudActivated, _) => Center(
            child: AnimatedOpacity(
              opacity: cloudActivated ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Icon(
                Icons.cloud,
                size: 24,
                color: Theme.of(context).colorScheme.secondary,
                shadows: const [Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Selector<LyfiViewModel, RssiLevel?>(
          selector: (_, vm) => vm.rssiLevel,
          builder: (content, rssi, _) => Center(
            child: switch (rssi) {
              null => Icon(Icons.wifi_off, size: 24, color: Theme.of(context).colorScheme.error),
              RssiLevel.strong => const Icon(Icons.wifi_rounded, size: 24),
              RssiLevel.medium => const Icon(Icons.wifi_2_bar_rounded, size: 24),
              RssiLevel.weak => const Icon(Icons.wifi_1_bar_rounded, size: 24),
            },
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

/// Top linear busy indicator under the AppBar
class LyfiBusyIndicatorSliver extends StatelessWidget {
  const LyfiBusyIndicatorSliver({super.key});
  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Selector<LyfiViewModel, ({bool isBusy, EditorStatus editorStatus})>(
        selector: (_, vm) => (isBusy: vm.isBusy, editorStatus: vm.editorState.status),
        builder: (context, state, _) {
          final theme = Theme.of(context);
          final isActive = state.isBusy || state.editorStatus == EditorStatus.loading;
          return SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(isActive ? theme.colorScheme.primary : Colors.transparent),
            ),
          );
        },
      ),
    );
  }
}

class LyfiStatusBannersSliver extends StatelessWidget {
  const LyfiStatusBannersSliver({super.key});

  @override
  Widget build(BuildContext context) {
    // timezone mismatch banner has been removed; no status banners at the moment
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
}
