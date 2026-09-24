import 'package:flutter/material.dart';

const String kSansFamily = 'IBM Plex Sans';
const String kMonoFamily = 'JetBrains Mono';

/// Palette tối (mặc định). Widget KHÔNG đọc trực tiếp class này — dùng
/// `context.palette` để tự đổi theo chế độ sáng/tối.
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

/// Palette sáng: cùng vai trò token với [AppColors], chỉnh độ đậm để chữ và
/// viền vẫn đạt tương phản trên nền trắng.
abstract final class AppLightColors {
  static const Color surface = Color(0xFFF6F7F9);
  static const Color surfaceRaised = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFF8C95A1);
  static const Color ink = Color(0xFF14171C);
  static const Color inkMuted = Color(0xFF535C68);
  static const Color primary = Color(0xFF0B7A61);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFF5B94A);
  static const Color onAccent = Color(0xFF2A1A00);
  static const Color danger = Color(0xFFC4352B);
}

/// Bộ màu đang dùng, gắn vào [ThemeData.extensions] để widget đọc qua
/// `context.palette`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.ink,
    required this.inkMuted,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.danger,
  });

  static const AppPalette dark = AppPalette(
    surface: AppColors.surface,
    surfaceRaised: AppColors.surfaceRaised,
    outline: AppColors.outline,
    ink: AppColors.ink,
    inkMuted: AppColors.inkMuted,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    accent: AppColors.accent,
    onAccent: AppColors.onAccent,
    danger: AppColors.danger,
  );

  static const AppPalette light = AppPalette(
    surface: AppLightColors.surface,
    surfaceRaised: AppLightColors.surfaceRaised,
    outline: AppLightColors.outline,
    ink: AppLightColors.ink,
    inkMuted: AppLightColors.inkMuted,
    primary: AppLightColors.primary,
    onPrimary: AppLightColors.onPrimary,
    accent: AppLightColors.accent,
    onAccent: AppLightColors.onAccent,
    danger: AppLightColors.danger,
  );

  final Color surface;
  final Color surfaceRaised;
  final Color outline;
  final Color ink;
  final Color inkMuted;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color onAccent;
  final Color danger;

  @override
  AppPalette copyWith({
    Color? surface,
    Color? surfaceRaised,
    Color? outline,
    Color? ink,
    Color? inkMuted,
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? onAccent,
    Color? danger,
  }) {
    return AppPalette(
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      outline: outline ?? this.outline,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// Palette theo theme hiện tại; thiếu extension (test dựng MaterialApp
  /// trần) thì rơi về palette tối.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
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

ThemeData buildAppTheme({Brightness brightness = Brightness.dark}) {
  final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final base = brightness == Brightness.dark
      ? const ColorScheme.dark()
      : const ColorScheme.light();
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: p.surface,
    focusColor: p.primary,
    extensions: [p],
    colorScheme: base.copyWith(
      surface: p.surface,
      surfaceContainer: p.surfaceRaised,
      outline: p.outline,
      onSurface: p.ink,
      onSurfaceVariant: p.inkMuted,
      primary: p.primary,
      onPrimary: p.onPrimary,
      tertiary: p.accent,
      onTertiary: p.onAccent,
      error: p.danger,
    ),
    cardTheme: const CardThemeData(elevation: 0),
    dialogTheme: const DialogThemeData(elevation: 0),
    bottomSheetTheme: const BottomSheetThemeData(elevation: 0),
    appBarTheme: const AppBarTheme(elevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: p.surface,
      indicatorColor: p.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => AppText.caption.copyWith(
          color: states.contains(WidgetState.selected) ? p.primary : p.inkMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? p.primary : p.inkMuted,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primary.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.primary : p.ink,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.outline)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: p.primary, width: 2),
      ),
    ),
    textTheme: TextTheme(
      displayLarge: AppText.display.copyWith(color: p.ink),
      titleLarge: AppText.title.copyWith(color: p.ink),
      bodyMedium: AppText.body.copyWith(color: p.ink),
      labelMedium: AppText.label.copyWith(color: p.ink),
      bodySmall: AppText.caption.copyWith(color: p.ink),
    ),
  );
}
