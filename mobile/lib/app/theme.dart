import 'package:flutter/material.dart';

const String kSansFamily = 'IBM Plex Sans';
const String kMonoFamily = 'JetBrains Mono';

abstract final class AppColors {
  static const Color surface = Color(0xFF111418);
  static const Color surfaceRaised = Color(0xFF1b1f25);
  static const Color outline = Color(0xFF626b78);
  static const Color ink = Color(0xFFe7e9ee);
  static const Color inkMuted = Color(0xFF9aa3b0);
  static const Color primary = Color(0xFF5ccfb0);
  static const Color onPrimary = Color(0xFF06231b);
  static const Color accent = Color(0xFFf5b94a);
  static const Color onAccent = Color(0xFF2a1a00);
  static const Color danger = Color(0xFFff7b72);
}

abstract final class AppSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s4 = 16;
  static const double s6 = 24;
}

abstract final class AppRadius {
  static const double sm = 6;
  static const double md = 12;
  static const double pill = 999;
}

abstract final class AppText {
  static const TextStyle display = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle title = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle code = TextStyle(
    fontFamily: kMonoFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.surface,
    focusColor: AppColors.primary,
    colorScheme: ColorScheme.dark(
      surface: AppColors.surface,
      surfaceContainer: AppColors.surfaceRaised,
      outline: AppColors.outline,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      tertiary: AppColors.accent,
      onTertiary: AppColors.onAccent,
      error: AppColors.danger,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
    ),
    dialogTheme: const DialogThemeData(
      elevation: 0,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      elevation: 0,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(
          color: AppColors.primary,
          width: 2,
        ),
      ),
    ),
    textTheme: TextTheme(
      displayLarge: AppText.display.copyWith(color: AppColors.ink),
      titleLarge: AppText.title.copyWith(color: AppColors.ink),
      bodyMedium: AppText.body.copyWith(color: AppColors.ink),
      labelMedium: AppText.label.copyWith(color: AppColors.ink),
      bodySmall: AppText.caption.copyWith(color: AppColors.ink),
    ),
  );
}
