import 'package:borneo_app/core/providers.dart';
import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/features/devices/providers/group_edit_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy;

import 'package:borneo_app/shared/widgets/confirmation_sheet.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Route-level shell.  Reads the legacy [IGroupManager] service from the
/// existing provider tree, then exposes both it and the route arguments as
/// Riverpod provider overrides so that the inner [_GroupEditBody] can be a
/// pure Riverpod consumer.
class GroupEditScreen extends StatelessWidget {
  final GroupEditArguments args;

  const GroupEditScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    final groupManager = legacy.Provider.of<IGroupManager>(context, listen: false);

    return ProviderScope(
      overrides: [
        groupManagerProvider.overrideWithValue(groupManager),
        groupEditArgsProvider.overrideWithValue(args),
        groupEditProvider.overrideWith(GroupEditNotifier.new),
      ],
      child: _GroupEditBody(args: args),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen body
// ---------------------------------------------------------------------------

class _GroupEditBody extends ConsumerStatefulWidget {
  final GroupEditArguments args;

  const _GroupEditBody({required this.args});

  @override
  ConsumerState<_GroupEditBody> createState() => _GroupEditBodyState();
}

class _GroupEditBodyState extends ConsumerState<_GroupEditBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.args.model?.name ?? '');
    _notesController = TextEditingController(text: widget.args.model?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Form fields
  // ---------------------------------------------------------------------------

  List<Widget> _buildFormFields(BuildContext context) {
    return [
      TextFormField(
        key: const Key('field_group_name'),
        controller: _nameController,
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
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _notesController,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(
          hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor),
          hintText: context.translate('Enter the optional notes for this scene'),
          labelText: context.translate('Notes'),
        ),
      ),
      const SizedBox(height: 24),
      Consumer(
        builder: (context, ref, _) {
          final isBusy = ref.watch(groupEditProvider.select((s) => s.isBusy));
          return FilledButton(
            key: const Key('btn_submit'),
            onPressed: isBusy ? null : () => _onSubmitPressed(context),
            child: isBusy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.translate('Submit')),
          );
        },
      ),
    ];
  }

  Widget _buildBody(BuildContext context) {
    final fields = _buildFormFields(context);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Form(
        key: _formKey,
        child: ListView.builder(
          shrinkWrap: true,
          itemBuilder: (context, index) => fields[index],
          itemCount: fields.length,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AppBar actions
  // ---------------------------------------------------------------------------

  List<Widget> _buildActions(BuildContext context) {
    if (widget.args.isCreation) return const [];

    return [
      TextButton(
        key: const Key('btn_delete_group'),
        onPressed: () => _onDeletePressed(context),
        child: Text(context.translate('Delete')),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Submit logic
  // ---------------------------------------------------------------------------

  bool _validateForm() {
    return _formKey.currentState?.validate() ?? false;
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _onSubmitPressed(BuildContext context) {
    if (!_validateForm()) return;

    final name = _nameController.text;
    final notes = _notesController.text;
    final navigator = Navigator.of(context);
    final notificationService = legacy.Provider.of<IAppNotificationService>(context, listen: false);
    final failureText = context.translate('Operation failed');

    _showLoadingDialog(context);

    ref
        .read(groupEditProvider.notifier)
        .submit(name: name, notes: notes)
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
  // Delete logic
  // ---------------------------------------------------------------------------

  Future<void> _onDeletePressed(BuildContext context) async {
    final state = ref.read(groupEditProvider);
    final notificationService = legacy.Provider.of<IAppNotificationService>(context, listen: false);
    final navigator = Navigator.of(context);

    final confirmed = await AsyncConfirmationSheet.show(
      context,
      message: context.translate(
        'Are you sure you want to delete "{0}" group?\n\nDevices in this group will be moved to the "Ungrouped" area.',
        pArgs: [state.name],
      ),
    );

    if (!confirmed) return;
    if (!context.mounted) return;

    final loadingNavigator = Navigator.of(context, rootNavigator: false);
    showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(groupEditProvider.notifier).delete();
      if (context.mounted) {
        loadingNavigator.pop(); // dismiss loading dialog
        if (navigator.mounted && navigator.canPop()) {
          navigator.pop(true); // return success to caller
        }
        notificationService.showSuccess(context.translate('Group deleted'));
      }
    } catch (error) {
      if (context.mounted) {
        loadingNavigator.pop(); // dismiss loading dialog
        notificationService.showError(context.translate('Delete failed'), body: error.toString());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final gt = GettextLocalizations.of(context);
    final isCreation = ref.watch(groupEditProvider.select((s) => s.isCreation));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(isCreation ? gt.translate('New Device Group') : gt.translate('Edit Device Group')),
        actions: _buildActions(context),
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }
}
