import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const accent = Color(0xFF0A84FF);
  static const accentSecondary = Color(0xFF5E5CE6);
  static const success = Color(0xFF30D158);
  static const warning = Color(0xFFFF9F0A);
  static const danger = Color(0xFFFF453A);

  static const darkBg = Color(0xFF000000);
  static const darkSurface = Color(0xFF1C1C1E);
  static const darkSurfaceElevated = Color(0xFF2C2C2E);
  static const darkBorder = Color(0xFF3A3A3C);

  static const lightBg = Color(0xFFF2F2F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceElevated = Color(0xFFF9F9FB);
  static const lightBorder = Color(0xFFE5E5EA);
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Plus Jakarta Sans';

  static TextStyle get _baseFont => GoogleFonts.plusJakartaSans();

  static TextTheme _materialTextTheme(Brightness brightness) {
    final seed = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    return GoogleFonts.plusJakartaSansTextTheme(seed);
  }

  static CupertinoTextThemeData _cupertinoTextTheme({
    required Brightness brightness,
    required Color primary,
    required Color secondary,
  }) {
    return CupertinoTextThemeData(
      textStyle: _baseFont.copyWith(fontSize: 17, color: primary),
      actionTextStyle: _baseFont.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.accent,
      ),
      navTitleTextStyle: _baseFont.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: primary,
      ),
      navLargeTitleTextStyle: _baseFont.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: primary,
      ),
      tabLabelTextStyle: _baseFont.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: secondary,
      ),
      pickerTextStyle: _baseFont.copyWith(fontSize: 22, color: primary),
    );
  }

  static ThemeData get dark {
    const brightness = Brightness.dark;
    final textTheme = _materialTextTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: AppColors.darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accentSecondary,
        surface: AppColors.darkSurface,
        error: AppColors.danger,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: AppColors.accent,
        barBackgroundColor: AppColors.darkSurface,
        scaffoldBackgroundColor: AppColors.darkBg,
        textTheme: _cupertinoTextTheme(
          brightness: brightness,
          primary: Colors.white,
          secondary: Colors.white.withValues(alpha: 0.6),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: _baseFont.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: Colors.white,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      dividerColor: AppColors.darkBorder,
      cardColor: AppColors.darkSurface,
    );
  }

  static ThemeData get light {
    const brightness = Brightness.light;
    final textTheme = _materialTextTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      scaffoldBackgroundColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        secondary: AppColors.accentSecondary,
        surface: AppColors.lightSurface,
        error: AppColors.danger,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: AppColors.accent,
        barBackgroundColor: AppColors.lightSurface,
        scaffoldBackgroundColor: AppColors.lightBg,
        textTheme: _cupertinoTextTheme(
          brightness: brightness,
          primary: Colors.black,
          secondary: Colors.black.withValues(alpha: 0.55),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightBg,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: _baseFont.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: Colors.black,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      dividerColor: AppColors.lightBorder,
      cardColor: AppColors.lightSurface,
    );
  }

  /// Estilo base para textos custom — hereda la fuente de la app.
  static TextStyle text(
    BuildContext context, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return _baseFont.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? labelPrimary(context),
      letterSpacing: letterSpacing,
      height: height,
      decoration: TextDecoration.none,
    );
  }

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color surface(BuildContext context) =>
      isDark(context) ? AppColors.darkSurface : AppColors.lightSurface;

  static Color surfaceElevated(BuildContext context) => isDark(context)
      ? AppColors.darkSurfaceElevated
      : AppColors.lightSurfaceElevated;

  static Color border(BuildContext context) =>
      isDark(context) ? AppColors.darkBorder : AppColors.lightBorder;

  static Color labelPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : Colors.black;

  static Color labelSecondary(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.6)
      : Colors.black.withValues(alpha: 0.55);
}
