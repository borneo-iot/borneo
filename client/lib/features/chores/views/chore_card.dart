import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/abstract_chore.dart';
import '../providers/chore_summary_provider.dart';

class ChoreCard extends ConsumerStatefulWidget {
  final AbstractChore chore;
  const ChoreCard(this.chore, {super.key});

  @override
  ConsumerState<ChoreCard> createState() => _ChoreCardState();
}

class _ChoreCardState extends ConsumerState<ChoreCard> {
  static const _disabledGrayscaleMatrix = <double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(choreSummaryProvider(widget.chore).notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(choreSummaryProvider(widget.chore));
    final notifier = ref.read(choreSummaryProvider(widget.chore).notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = state.isActive;
    final applicableDeviceCount = state.applicableDeviceCount;
    final isSwitchEnabled = !state.isBusy && applicableDeviceCount > 0;
    final bgColor = isActive ? colorScheme.primaryContainer : colorScheme.surfaceContainer;
    final fgColor = isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
    final effectiveFgColor = isSwitchEnabled ? fgColor : fgColor.withValues(alpha: 0.45);
    final effectiveSecondaryFgColor = isSwitchEnabled
        ? fgColor.withValues(alpha: 0.7)
        : fgColor.withValues(alpha: 0.35);
    final iconOpacity = isSwitchEnabled ? 1.0 : 0.4;
    const kAnimateDuration = Duration(milliseconds: 300);
    final textTheme = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: kAnimateDuration,
            curve: Curves.easeInOut,
            color: bgColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final iconSize = (constraints.maxHeight - 16.0).clamp(0.0, double.infinity);
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Opacity(
                            opacity: iconOpacity,
                            child: _buildIcon(widget.chore.iconAssetPath, iconSize, isEnabled: isSwitchEnabled),
                          ),
                        );
                      },
                    ),
                  ),
                  Text(
                    widget.chore.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: textTheme.labelLarge?.fontSize, color: effectiveFgColor),
                  ),
                  Divider(height: 16, thickness: 1.5, color: effectiveSecondaryFgColor.withValues(alpha: 0.3)),
                  Row(
                    children: [
                      AnimatedSwitcher(
                        duration: kAnimateDuration,
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isActive ? context.translate('ACTIVE') : context.translate('INACTIVE'),
                            key: ValueKey(isActive),
                            style: TextStyle(
                              fontSize: textTheme.labelSmall?.fontSize,
                              color: effectiveSecondaryFgColor,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Switch.adaptive(
                        key: Key('chore_switch_${widget.chore.id}'),
                        value: isActive,
                        onChanged: isSwitchEnabled ? (v) => v ? notifier.executeChore() : notifier.undoChore() : null,
                        activeThumbColor: colorScheme.onPrimary,
                        activeTrackColor: colorScheme.primary,
                        inactiveThumbColor: colorScheme.onSurfaceVariant,
                        inactiveTrackColor: colorScheme.surfaceBright,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: _buildDeviceCountBadge(context, applicableDeviceCount: applicableDeviceCount, isActive: isActive),
          ),
          // Execution progress overlay removed per request (no animation)
        ],
      ),
    );
  }

  Widget _buildDeviceCountBadge(BuildContext context, {required int applicableDeviceCount, required bool isActive}) {
    final colorScheme = Theme.of(context).colorScheme;
    final badgeGradient = LinearGradient(
      colors: isActive
          ? [colorScheme.primary.withValues(alpha: 0.95), colorScheme.tertiary.withValues(alpha: 0.88)]
          : [colorScheme.surface.withValues(alpha: 0.96), colorScheme.surfaceContainerHigh],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final textColor = isActive ? colorScheme.onPrimary : colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: badgeGradient,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: textColor.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.12), blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_rounded, size: 13, color: textColor.withValues(alpha: 0.88)),
            const SizedBox(width: 5),
            Text(
              '$applicableDeviceCount',
              key: Key('chore_device_count_${widget.chore.id}'),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: textColor, fontWeight: FontWeight.w800, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(String iconAssetPath, double iconSize, {required bool isEnabled}) {
    final icon = iconAssetPath.endsWith('.svg')
        ? SvgPicture.asset(iconAssetPath, height: iconSize, width: iconSize)
        : Image.asset(iconAssetPath, height: iconSize, width: iconSize);

    if (isEnabled) {
      return icon;
    }

    return ColorFiltered(colorFilter: const ColorFilter.matrix(_disabledGrayscaleMatrix), child: icon);
  }
}
