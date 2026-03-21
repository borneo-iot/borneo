import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_ui/flutter_settings_ui.dart';

SettingsThemeData settingsListTheme(BuildContext context, {DevicePlatform? platform}) {
  final resolvedPlatform = platform ?? _resolvePlatform(context);

  switch (resolvedPlatform) {
    case DevicePlatform.android:
    case DevicePlatform.fuchsia:
    case DevicePlatform.linux:
      return _androidTheme(context: context);
    case DevicePlatform.iOS:
    case DevicePlatform.macOS:
    case DevicePlatform.windows:
      return _iosTheme(context: context);
    case DevicePlatform.web:
      return _webTheme(context: context);
    case DevicePlatform.device:
      throw Exception("You can't use the DevicePlatform.device in this context. Incorrect platform: settingsListTheme");
  }
}

DevicePlatform _resolvePlatform(BuildContext context) {
  if (kIsWeb) {
    return DevicePlatform.web;
  }

  return switch (Theme.of(context).platform) {
    TargetPlatform.android => DevicePlatform.android,
    TargetPlatform.fuchsia => DevicePlatform.fuchsia,
    TargetPlatform.iOS => DevicePlatform.iOS,
    TargetPlatform.macOS => DevicePlatform.macOS,
    TargetPlatform.windows => DevicePlatform.windows,
    TargetPlatform.linux => DevicePlatform.linux,
  };
}

SettingsThemeData _androidTheme({required BuildContext context}) {
  final colorScheme = Theme.of(context).colorScheme;

  return SettingsThemeData(
    settingsListBackground: Colors.transparent,
    settingsSectionBackground: colorScheme.surfaceContainerLow,
    dividerColor: colorScheme.outlineVariant,
    tileHighlightColor: colorScheme.surfaceContainerHighest,
    titleTextColor: colorScheme.primary,
    trailingTextColor: colorScheme.onSurfaceVariant,
    settingsTileTextColor: colorScheme.onSurface,
    leadingIconsColor: colorScheme.onSurfaceVariant,
    tileDescriptionTextColor: colorScheme.onSurfaceVariant,
    inactiveTitleColor: colorScheme.onSurface.withValues(alpha: 0.38),
    inactiveSubtitleColor: colorScheme.onSurfaceVariant.withValues(alpha: .38),
  );
}

SettingsThemeData _iosTheme({required BuildContext context}) {
  final colorScheme = Theme.of(context).colorScheme;

  return SettingsThemeData(
    settingsListBackground: CupertinoColors.systemGroupedBackground.resolveFrom(context),
    settingsSectionBackground: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
    dividerColor: CupertinoColors.separator.resolveFrom(context),
    tileHighlightColor: colorScheme.surfaceContainerHighest,
    titleTextColor: CupertinoColors.secondaryLabel.resolveFrom(context),
    trailingTextColor: CupertinoColors.secondaryLabel.resolveFrom(context),
    settingsTileTextColor: CupertinoColors.label.resolveFrom(context),
    leadingIconsColor: CupertinoColors.secondaryLabel.resolveFrom(context),
    tileDescriptionTextColor: CupertinoColors.secondaryLabel.resolveFrom(context),
    inactiveTitleColor: CupertinoColors.tertiaryLabel.resolveFrom(context),
    inactiveSubtitleColor: CupertinoColors.tertiaryLabel.resolveFrom(context),
  );
}

SettingsThemeData _webTheme({required BuildContext context}) {
  final colorScheme = Theme.of(context).colorScheme;

  return SettingsThemeData(
    settingsListBackground: colorScheme.surface,
    settingsSectionBackground: colorScheme.surfaceContainerLow,
    dividerColor: colorScheme.outlineVariant,
    tileHighlightColor: colorScheme.surfaceContainerHighest,
    titleTextColor: colorScheme.primary,
    trailingTextColor: colorScheme.onSurfaceVariant,
    settingsTileTextColor: colorScheme.onSurface,
    leadingIconsColor: colorScheme.onSurfaceVariant,
    tileDescriptionTextColor: colorScheme.onSurfaceVariant,
    inactiveTitleColor: colorScheme.onSurface.withValues(alpha: 0.38),
    inactiveSubtitleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
  );
}
