import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext/context_ext.dart';

class GenericSettingsScreen extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget>? appBarActions;

  const GenericSettingsScreen({super.key, required this.children, this.title = 'Settings', this.appBarActions});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: appBarActions),
      body: ListView.builder(itemCount: children.length, itemBuilder: (context, index) => children[index]),
    );
  }
}

class GenericSettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const GenericSettingsGroup({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).scaffoldBackgroundColor;
    final tiles = <Widget>[
      ListTile(
        dense: true,
        tileColor: dividerColor,
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
        ),
      ),
    ];

    for (var i = 0; i < children.length; i++) {
      tiles.add(children[i]);
      if (i != children.length - 1) {
        tiles.add(Divider(height: 0, color: dividerColor));
      }
    }

    return Column(mainAxisSize: MainAxisSize.min, children: tiles);
  }
}

class SaveButton extends StatelessWidget {
  const SaveButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(context.translate('Save')),
      onTap: () {
        // Save action
      },
    );
  }
}

class CancelButton extends StatelessWidget {
  const CancelButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(context.translate('Cancel')),
      onTap: () {
        // Cancel action
      },
    );
  }
}
