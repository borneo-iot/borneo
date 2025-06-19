import 'dart:async';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import 'package:borneo_app/features/routines/view_models/routine_summary_view_model.dart';

class RoutineCard extends StatelessWidget {
  final RoutineSummaryViewModel viewModel;
  const RoutineCard(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: viewModel,
      builder: (context, child) {
        final colorScheme = Theme.of(context).colorScheme;
        return Consumer<RoutineSummaryViewModel>(
          builder: (context, vm, _) {
            final isBusy = vm.isBusy.value;
            final isActive = vm.isActive;
            final bgColor = isActive ? colorScheme.primaryContainer : colorScheme.surfaceContainer;
            final fgColor = isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurface;
            return _RoutineCardContent(
              isBusy: isBusy,
              bgColor: bgColor,
              fgColor: fgColor,
              vm: vm,
              colorScheme: colorScheme,
              isActive: isActive,
            );
          },
        );
      },
    );
  }
}

class _RoutineCardContent extends StatefulWidget {
  final bool isBusy;
  final Color bgColor;
  final Color fgColor;
  final RoutineSummaryViewModel vm;
  final ColorScheme colorScheme;
  final bool isActive;
  const _RoutineCardContent({
    required this.isBusy,
    required this.bgColor,
    required this.fgColor,
    required this.vm,
    required this.colorScheme,
    required this.isActive,
  });

  @override
  State<_RoutineCardContent> createState() => _RoutineCardContentState();
}

class _RoutineCardContentState extends State<_RoutineCardContent> {
  bool _showProgress = false;
  Timer? _timer;

  @override
  void didUpdateWidget(covariant _RoutineCardContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBusy && !_showProgress) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 800), () {
        if (mounted && widget.isBusy) {
          setState(() => _showProgress = true);
        }
      });
    } else if (!widget.isBusy) {
      _timer?.cancel();
      if (_showProgress) setState(() => _showProgress = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final bgColor = widget.bgColor;
    final fgColor = widget.fgColor;
    final colorScheme = widget.colorScheme;
    final isActive = widget.isActive;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Card.filled(
            margin: EdgeInsets.all(0),
            elevation: 0,
            color: bgColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                child: Column(
                  key: ValueKey(isActive.toString() + vm.name),
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          final iconSize = constraints.maxHeight - 16.0;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: SvgPicture.asset(vm.iconAssetPath, height: iconSize, width: iconSize),
                          );
                        },
                      ),
                    ),
                    Selector<RoutineSummaryViewModel, String>(
                      selector: (context, vm) => vm.name,
                      builder: (_, routineName, child) => Text(
                        routineName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.0, color: fgColor),
                      ),
                    ),
                    Divider(height: 16, thickness: 1, color: fgColor.withValues(alpha: 0.2)),
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Text(
                          isActive ? context.translate('ACTIVE') : context.translate('INACTIVE'),
                          style: TextStyle(fontSize: 12, color: fgColor.withValues(alpha: 0.7)),
                        ),
                        Spacer(),
                        Switch(
                          value: isActive,
                          onChanged: widget.isBusy
                              ? null
                              : (v) async {
                                  if (v) {
                                    await vm.executeRoutine();
                                  } else {
                                    await vm.undoRoutine();
                                  }
                                },
                          activeColor: colorScheme.primary,
                          inactiveThumbColor: colorScheme.primary,
                          inactiveTrackColor: colorScheme.surfaceBright,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showProgress && widget.isBusy)
            Positioned.fill(
              child: Container(
                color: bgColor.withValues(alpha: 0.6),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
