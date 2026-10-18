import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

/// DgadenVPN brand colors.
abstract class BrandColors {
  static const primary = Color(0xFF1E88FF);
  static const accent = Color(0xFF2EE6FF);
  static const background = Color(0xFF0B0F1A);
  static const surface = Color(0xFF121A2B);
  static const connected = Color(0xFF22C55E);
  static const disconnected = Color(0xFFEF4444);
}

class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  ThemeData lightTheme(ColorScheme? lightColorScheme) {
    // Brand colors always win over the system (wallpaper) palette.
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: BrandColors.primary, primary: BrandColors.primary);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  ThemeData darkTheme(ColorScheme? darkColorScheme) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.primary,
      brightness: Brightness.dark,
      primary: BrandColors.primary,
      onPrimary: Colors.white,
      secondary: BrandColors.accent,
      surface: mode.trueBlack ? Colors.black : BrandColors.background,
      surfaceContainerLowest: BrandColors.background,
      surfaceContainerLow: const Color(0xFF0F1626),
      surfaceContainer: BrandColors.surface,
      surfaceContainerHigh: const Color(0xFF172238),
      surfaceContainerHighest: const Color(0xFF1C2944),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: mode.trueBlack ? Colors.black : BrandColors.background,
      appBarTheme: AppBarTheme(backgroundColor: mode.trueBlack ? Colors.black : BrandColors.background),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: BrandColors.surface),
      navigationRailTheme: const NavigationRailThemeData(backgroundColor: BrandColors.background),
      fontFamily: fontFamily,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.light},
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark, ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
    final bool isDark = switch (mode) {
      AppThemeMode.system => sysDark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
      AppThemeMode.black => true,
    };
    final def = CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light);
    // final def = CupertinoThemeData(brightness: Brightness.dark);

    // return def;
    final defaultMaterialTheme = isDark ? darkTheme(darkColorScheme) : lightTheme(lightColorScheme);
    return MaterialBasedCupertinoThemeData(
      materialTheme: defaultMaterialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: fontFamily),
          ).copyWith(),
          barBackgroundColor: def.barBackgroundColor,
          scaffoldBackgroundColor: def.scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
