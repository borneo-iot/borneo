import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

SystemUiOverlayStyle borneoSystemUiOverlayStyle(
  ThemeData theme, {
  Brightness? systemNavigationBarIconBrightness,
  Color? systemNavigationBarDividerColor,
  bool systemNavigationBarContrastEnforced = false,
  bool systemStatusBarContrastEnforced = false,
}) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: theme.brightness,
    systemNavigationBarColor: theme.colorScheme.surfaceContainer,
    systemNavigationBarDividerColor:
        systemNavigationBarDividerColor ??
        (theme.colorScheme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceBright
            : theme.colorScheme.surfaceDim),
    systemNavigationBarIconBrightness: systemNavigationBarIconBrightness,
    systemNavigationBarContrastEnforced: systemNavigationBarContrastEnforced,
    systemStatusBarContrastEnforced: systemStatusBarContrastEnforced,
  );
}
