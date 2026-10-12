import 'package:flutter/material.dart';

const String kSansFamily = 'Nunito';
const String kMonoFamily = 'JetBrains Mono';

/// Palette tối (The Coach, `data-app="dark"`). Widget KHÔNG đọc trực tiếp
/// class này — dùng `context.palette` để tự đổi theo chế độ sáng/tối.
abstract final class AppColors {
  static const Color surface = Color(0xFF0F1522);
  static const Color surfaceRaised = Color(0xFF171F31);
  static const Color outline = Color(0xFF27314A);
  static const Color ink = Color(0xFFE8ECF4);
  static const Color inkMuted = Color(0xFF9AA6BA);
  static const Color primary = Color(0xFF6C9DF0);
  static const Color onPrimary = Color(0xFF0F1522);
  static const Color accent = Color(0xFFFF8A00);
  static const Color onAccent = Color(0xFF2A1A00);
  static const Color danger = Color(0xFFE5484D);
  static const Color primaryDark = Color(0xFF3E6FC8);
  static const Color primarySoft = Color(0xFF1D2A47);
  static const Color success = Color(0xFF58A700);
  static const Color successDark = Color(0xFF3F7D00);
  static const Color successSoft = Color(0xFF1C3314);
  static const Color codeSurface = Color(0xFF0C111C);
  static const Color codeInk = Color(0xFFE6E9F2);
}

/// Palette sáng (The Coach, mặc định): cùng vai trò token với [AppColors].
abstract final class AppLightColors {
  static const Color surface = Color(0xFFF7F8FA);
  static const Color surfaceRaised = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFE5E7EB);
  static const Color ink = Color(0xFF14213D);
  static const Color inkMuted = Color(0xFF6B7280);
  static const Color primary = Color(0xFF4A86E8);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFFF8A00);
  static const Color onAccent = Color(0xFF2A1A00);
  static const Color danger = Color(0xFFE5484D);
  static const Color primaryDark = Color(0xFF2F6BCB);
  static const Color primarySoft = Color(0xFFE8F0FB);
  static const Color success = Color(0xFF58A700);
  static const Color successDark = Color(0xFF3F7D00);
  static const Color successSoft = Color(0xFFE4F0D5);
  static const Color codeSurface = Color(0xFF1E2230);
  static const Color codeInk = Color(0xFFE6E9F2);
}

/// Hai màu đầu/cuối của thẻ chủ đề (gradient 135deg trong mockup).
@immutable
class AppGradientPair {
  const AppGradientPair(this.start, this.end);

  final Color start;
  final Color end;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [start, end],
  );
}

/// 3 cặp màu thẻ chủ đề: g1 xanh dương, g2 teal, g3 tím. Chữ trên đó luôn
/// trắng nên dùng được ở cả hai theme.
abstract final class AppGradients {
  static const AppGradientPair g1 = AppGradientPair(
    Color(0xFF1E3A8A),
    Color(0xFF4A86E8),
  );
  static const AppGradientPair g2 = AppGradientPair(
    Color(0xFF0F5C5C),
    Color(0xFF2BA39A),
  );
  static const AppGradientPair g3 = AppGradientPair(
    Color(0xFF4B2A7B),
    Color(0xFF8B5CC6),
  );
  static const List<AppGradientPair> all = [g1, g2, g3];
}

/// Ngưỡng bề rộng duy nhất cho layout web: `nav` = bỏ bottom nav, dùng
/// drawer; `split` = màn luyện chia đôi.
abstract final class AppBreakpoint {
  static const double nav = 700.0;
  static const double split = 900.0;
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
    required this.primaryDark,
    required this.primarySoft,
    required this.success,
    required this.successDark,
    required this.successSoft,
    required this.codeSurface,
    required this.codeInk,
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
    primaryDark: AppColors.primaryDark,
    primarySoft: AppColors.primarySoft,
    success: AppColors.success,
    successDark: AppColors.successDark,
    successSoft: AppColors.successSoft,
    codeSurface: AppColors.codeSurface,
    codeInk: AppColors.codeInk,
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
    primaryDark: AppLightColors.primaryDark,
    primarySoft: AppLightColors.primarySoft,
    success: AppLightColors.success,
    successDark: AppLightColors.successDark,
    successSoft: AppLightColors.successSoft,
    codeSurface: AppLightColors.codeSurface,
    codeInk: AppLightColors.codeInk,
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
  final Color primaryDark;
  final Color primarySoft;
  final Color success;
  final Color successDark;
  final Color successSoft;
  final Color codeSurface;
  final Color codeInk;

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
    Color? primaryDark,
    Color? primarySoft,
    Color? success,
    Color? successDark,
    Color? successSoft,
    Color? codeSurface,
    Color? codeInk,
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
      primaryDark: primaryDark ?? this.primaryDark,
      primarySoft: primarySoft ?? this.primarySoft,
      success: success ?? this.success,
      successDark: successDark ?? this.successDark,
      successSoft: successSoft ?? this.successSoft,
      codeSurface: codeSurface ?? this.codeSurface,
      codeInk: codeInk ?? this.codeInk,
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
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      successDark: Color.lerp(successDark, other.successDark, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      codeSurface: Color.lerp(codeSurface, other.codeSurface, t)!,
      codeInk: Color.lerp(codeInk, other.codeInk, t)!,
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
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

abstract final class AppText {
  // Nunito là file variable: fontWeight chọn mặt chữ, fontVariations ép trục
  // `wght` thật sự áp dụng cho engine.
  static const TextStyle display = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w900,
    fontVariations: [FontVariation('wght', 900)],
  );

  static const TextStyle title = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w800,
    fontVariations: [FontVariation('wght', 800)],
  );

  static const TextStyle body = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
  );

  static const TextStyle label = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
  );

  static const TextStyle caption = TextStyle(
    fontFamily: kSansFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
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
      indicatorColor: p.primarySoft,
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
              ? p.primarySoft
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.primary : p.ink,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.outline, width: 2)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: p.outline, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
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
