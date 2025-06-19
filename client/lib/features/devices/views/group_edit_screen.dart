import 'package:borneo_app/core/services/group_manager.dart';
import 'package:borneo_app/features/devices/view_models/group_edit_view_model.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/confirmation_sheet.dart';

class GroupEditScreen extends StatelessWidget {
  final _formKey = GlobalKey<FormState>();

  GroupEditScreen({super.key});

  List<Widget> makePropertyTiles(BuildContext context) {
    final vm = context.read<GroupEditViewModel>();
    return [
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
      ElevatedButton(
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

  FutureBuilder buildBody(BuildContext context) {
    final vm = context.read<GroupEditViewModel>();
    return FutureBuilder(
      future: vm.initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Form(key: _formKey, child: buildList(context)),
          );
        }
      },
    );
  }

  List<Widget> buildActions(BuildContext context, GroupEditArguments args) {
    final vm = context.read<GroupEditViewModel>();
    return [
      if (!args.isCreation)
        IconButton(
          onPressed: () {
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

  @override
  Widget build(BuildContext context) {
    final GroupEditArguments args = ModalRoute.of(context)!.settings.arguments as GroupEditArguments;

    return ChangeNotifierProvider<GroupEditViewModel>(
      create: (context) => GroupEditViewModel(
        context.read<GroupManager>(),
        isCreation: args.isCreation,
        model: args.model,
        globalEventBus: context.read<EventBus>(),
        logger: context.read<Logger>(),
      ),
      builder: (context, child) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(args.isCreation ? context.translate('New Device Group') : context.translate('Edit Device Group')),
          actions: buildActions(context, args),
        ),
        body: buildBody(context),
      ),
    );
  }
}
