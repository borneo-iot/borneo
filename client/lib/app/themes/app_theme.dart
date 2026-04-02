import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

abstract final class BorneoTheme {
  static final ColorScheme lightScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff493b72),
    brightness: Brightness.light,
    surfaceTint: Colors.transparent,
  );

  static final lightTextTheme = Typography.material2021().black.copyWith(
    titleLarge: Typography.material2021().black.titleLarge?.copyWith(fontSize: 18),
  );

  static final light = FlexThemeData.light(
    colorScheme: lightScheme,
    textTheme: lightTextTheme,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 7,
    subThemesData: const FlexSubThemesData(blendOnLevel: 10, blendOnColors: false),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true,
    surfaceTint: Colors.transparent,
    scaffoldBackground: lightScheme.surfaceBright,

    appBarBackground: lightScheme.surfaceBright,
    appBarElevation: 0,
  );

  static final darkScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff493b72),
    brightness: Brightness.dark,
    surfaceTint: Colors.transparent,
  );

  static final darkTextTheme = Typography.material2021().white.copyWith(
    titleLarge: Typography.material2021().white.titleLarge?.copyWith(fontSize: 18),
  );

  static final dark = FlexThemeData.dark(
    colorScheme: darkScheme,
    textTheme: darkTextTheme,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 13,
    subThemesData: const FlexSubThemesData(blendOnLevel: 20),
    useMaterial3: true,
    surfaceTint: Colors.transparent,
    scaffoldBackground: darkScheme.surfaceDim,

    appBarBackground: darkScheme.surfaceDim,
    appBarElevation: 0,
  );
}
