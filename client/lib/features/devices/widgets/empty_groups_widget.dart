import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

/// Widget displayed when no device groups exist
class EmptyGroupsWidget extends StatelessWidget {
  final VoidCallback onCreateGroup;

  const EmptyGroupsWidget({required this.onCreateGroup, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            Text(
              context.translate('No Devices'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 8),
            Text(
              context.translate('Add devices to get started'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreateGroup,
              icon: const Icon(Icons.add),
              label: Text(context.translate('Add Devices')),
            ),
          ],
        ),
      ),
    );
  }
}
