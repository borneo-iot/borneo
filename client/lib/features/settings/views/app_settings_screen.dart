import 'package:borneo_app/core/services/app_notification_service.dart';
import 'package:borneo_app/core/services/url_launcher_service.dart';
import 'package:borneo_app/shared/widgets/generic_bottom_sheet_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gettext/flutter_gettext.dart';
import 'package:flutter_settings_ui/flutter_settings_ui.dart';
import 'package:logger/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import 'package:borneo_app/features/settings/providers/app_settings_provider.dart';
import 'package:borneo_app/core/config/language_config.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  static const String githubIssuesUrl = 'https://github.com/borneo-iot/borneo/issues';

  Future<void> _openUrl(BuildContext context, String url) async {
    final urlLauncher = UrlLauncherService(
      notification: provider.Provider.of<IAppNotificationService>(context, listen: false),
      logger: provider.Provider.of<Logger>(context, listen: false),
    );
    await urlLauncher.open(url);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(appSettingsProvider);

    return asyncState.when(
      loading: () => Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, st) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (state) {
        return Scaffold(
          appBar: AppBar(title: Text(context.translate('App Settings')), elevation: 1),
          body: buildItems(context, ref, state),
        );
      },
    );
  }

  SettingsList buildItems(BuildContext context, WidgetRef ref, AppSettingsState state) => SettingsList(
    sections: [
      SettingsSection(
        title: Text(context.translate('APPEARANCE')),
        tiles: [
          SettingsTile.navigation(
            leading: const Icon(Icons.settings_brightness_outlined),
            title: Text(context.translate('Theme')),
            value: Text(switch (state.themeMode) {
              ThemeMode.system => context.translate('System'),
              ThemeMode.light => context.translate('Light'),
              ThemeMode.dark => context.translate('Dark'),
            }),
            onPressed: (context) async {
              await GenericBottomSheetPicker.show<ThemeMode>(
                context: context,
                title: context.translate('Select Theme'),
                entries: [
                  GenericBottomSheetPickerEntry(value: ThemeMode.system, label: context.translate('System')),
                  GenericBottomSheetPickerEntry(value: ThemeMode.light, label: context.translate('Light')),
                  GenericBottomSheetPickerEntry(value: ThemeMode.dark, label: context.translate('Dark')),
                ],
                selectedValue: state.themeMode,
                onValueSelected: (val) => ref.read(appSettingsProvider.notifier).changeBrightness(val),
              );
            },
          ),
          SettingsTile.navigation(
            leading: Icon(Icons.language_outlined),
            title: Text(context.translate('Language')),
            value: Text(LanguageConfig.getLocaleDisplayName(state.locale ?? const Locale('en', 'US'))),
            onPressed: (context) async {
              final current = state.locale ?? const Locale('en', 'US');
              await GenericBottomSheetPicker.show<Locale>(
                context: context,
                title: context.translate('Select Language'),
                entries: LanguageConfig.supportedLocales
                    .map(
                      (loc) =>
                          GenericBottomSheetPickerEntry(value: loc, label: LanguageConfig.getLocaleDisplayName(loc)),
                    )
                    .toList(),
                selectedValue: current,
                onValueSelected: (val) {
                  ref.read(appSettingsProvider.notifier).changeLocale(val);
                },
              );
            },
          ),
          SettingsTile.navigation(
            leading: Icon(Icons.thermostat_outlined),
            title: Text(context.translate('Temperature Unit')),
            value: Text(switch (state.temperatureUnit) {
              'C' => context.translate('℃'),
              'F' => context.translate('℉'),
              _ => context.translate(''),
            }),
            onPressed: (context) async {
              await GenericBottomSheetPicker.show<String>(
                context: context,
                title: context.translate('Select Temperature Unit'),
                entries: [
                  GenericBottomSheetPickerEntry(value: 'C', label: context.translate('℃ (Celsius)')),
                  GenericBottomSheetPickerEntry(value: 'F', label: context.translate('℉ (Fahrenheit)')),
                ],
                selectedValue: state.temperatureUnit,
                onValueSelected: (val) => ref.read(appSettingsProvider.notifier).changeTemperatureUnit(val),
              );
            },
          ),
        ],
      ),

      SettingsSection(
        title: Text(context.translate('FEEDBACK')),
        tiles: [
          /*
          SettingsTile.navigation(
            leading: const Icon(Icons.star_outline),
            title: Text(context.translate('Rate in application store')),
          ),
          */
          SettingsTile.navigation(
            leading: const Icon(Icons.settings_brightness_outlined),
            title: Text(context.translate('Feedback via Email')),
            onPressed: (bc) => _openUrl(bc, 'mailto:support@binarystarstech.com'),
          ),
        ],
      ),
    ],
  );
}
