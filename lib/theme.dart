import 'package:flutter/material.dart';

/// Type families bundled in assets/fonts (OFL licensed).
/// Space Grotesk carries the identity; JetBrains Mono carries the data —
/// every byte size, count, and path in the app renders in mono.
const displayFamily = 'SpaceGrotesk';
const monoFamily = 'JetBrainsMono';

/// Data text style: tabular mono for sizes, counts, and paths.
TextStyle mono(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: monoFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Trust-tier colors used by the treemap, badges, and insights.
/// `protected` is deliberately recessive and always pairs with a lock icon so
/// meaning is never carried by color alone.
@immutable
class TierColors extends ThemeExtension<TierColors> {
  const TierColors({
    required this.safe,
    required this.review,
    required this.protected,
  });

  final Color safe;
  final Color review;
  final Color protected;

  static const light = TierColors(
    safe: Color(0xFF0E9F72),
    review: Color(0xFFC07C13),
    protected: Color(0xFF87908C),
  );

  static const dark = TierColors(
    safe: Color(0xFF2FD695),
    review: Color(0xFFE8A33D),
    protected: Color(0xFF707B76),
  );

  @override
  TierColors copyWith({Color? safe, Color? review, Color? protected}) {
    return TierColors(
      safe: safe ?? this.safe,
      review: review ?? this.review,
      protected: protected ?? this.protected,
    );
  }

  @override
  TierColors lerp(TierColors? other, double t) {
    if (other == null) return this;
    return TierColors(
      safe: Color.lerp(safe, other.safe, t)!,
      review: Color.lerp(review, other.review, t)!,
      protected: Color.lerp(protected, other.protected, t)!,
    );
  }
}

/// Treemap surface colors. Folders and files each get a sequential ramp
/// (bigger item → richer step) so the map reads as terrain; saturated color
/// stays reserved for meaning (tiers).
@immutable
class MapColors extends ThemeExtension<MapColors> {
  const MapColors({
    required this.folderHi,
    required this.folderLo,
    required this.fileHi,
    required this.fileLo,
    required this.chunk,
    required this.ink,
    required this.inkFaint,
  });

  /// Ramp endpoints: `Hi` is the biggest item in view, `Lo` the smallest.
  final Color folderHi;
  final Color folderLo;
  final Color fileHi;
  final Color fileLo;

  /// Flat fill for aggregates ("(small files)", "N more items").
  final Color chunk;

  /// Label ink on regular (non-tier) tiles.
  final Color ink;
  final Color inkFaint;

  Color folderAt(double t) => Color.lerp(folderHi, folderLo, t)!;
  Color fileAt(double t) => Color.lerp(fileHi, fileLo, t)!;

  static const dark = MapColors(
    folderHi: Color(0xFF3D5148),
    folderLo: Color(0xFF222B26),
    fileHi: Color(0xFF32424E),
    fileLo: Color(0xFF1F262C),
    chunk: Color(0xFF1B211E),
    ink: Color(0xFFE8EFEA),
    inkFaint: Color(0xFF9DAAA2),
  );

  static const light = MapColors(
    folderHi: Color(0xFFAEC9BE),
    folderLo: Color(0xFFE2ECE7),
    fileHi: Color(0xFFB4CBD9),
    fileLo: Color(0xFFE4EDF2),
    chunk: Color(0xFFEDF1EE),
    ink: Color(0xFF1C2420),
    inkFaint: Color(0xFF5A665F),
  );

  @override
  MapColors copyWith({
    Color? folderHi,
    Color? folderLo,
    Color? fileHi,
    Color? fileLo,
    Color? chunk,
    Color? ink,
    Color? inkFaint,
  }) {
    return MapColors(
      folderHi: folderHi ?? this.folderHi,
      folderLo: folderLo ?? this.folderLo,
      fileHi: fileHi ?? this.fileHi,
      fileLo: fileLo ?? this.fileLo,
      chunk: chunk ?? this.chunk,
      ink: ink ?? this.ink,
      inkFaint: inkFaint ?? this.inkFaint,
    );
  }

  @override
  MapColors lerp(MapColors? other, double t) {
    if (other == null) return this;
    return MapColors(
      folderHi: Color.lerp(folderHi, other.folderHi, t)!,
      folderLo: Color.lerp(folderLo, other.folderLo, t)!,
      fileHi: Color.lerp(fileHi, other.fileHi, t)!,
      fileLo: Color.lerp(fileLo, other.fileLo, t)!,
      chunk: Color.lerp(chunk, other.chunk, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
    );
  }
}

extension ThemeTokens on ThemeData {
  TierColors get tiers => extension<TierColors>()!;
  MapColors get map => extension<MapColors>()!;
}

/// "Deep forest" theme: near-black green-cast surfaces in dark mode, warm
/// paper in light, one minty accent, mono for data. No purple, no gradients
/// on chrome — color is reserved for the map and for meaning.
abstract final class CleanMindTheme {
  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF17BF8F),
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFF3ADFB4) : const Color(0xFF0B8E6A),
      onPrimary: isDark ? const Color(0xFF04231A) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF11332A) : const Color(0xFFCDEEE2),
      onPrimaryContainer:
          isDark ? const Color(0xFF8FE8CC) : const Color(0xFF0A4534),
      surface: isDark ? const Color(0xFF0E1210) : const Color(0xFFF7F8F6),
      onSurface: isDark ? const Color(0xFFE9EFEB) : const Color(0xFF171D1A),
      surfaceContainerLowest:
          isDark ? const Color(0xFF0A0D0C) : Colors.white,
      surfaceContainerLow:
          isDark ? const Color(0xFF131816) : const Color(0xFFFDFDFC),
      surfaceContainer:
          isDark ? const Color(0xFF171D1A) : const Color(0xFFF0F2EF),
      surfaceContainerHigh:
          isDark ? const Color(0xFF1C2320) : const Color(0xFFE9ECE8),
      surfaceContainerHighest:
          isDark ? const Color(0xFF232B27) : const Color(0xFFE2E6E1),
      onSurfaceVariant:
          isDark ? const Color(0xFF9DAAA3) : const Color(0xFF49534E),
      outline: isDark ? const Color(0xFF5C6963) : const Color(0xFF79837D),
      outlineVariant:
          isDark ? const Color(0xFF262E2A) : const Color(0xFFDCE1DC),
      inverseSurface:
          isDark ? const Color(0xFFE9EFEB) : const Color(0xFF232B27),
      error: isDark ? const Color(0xFFEF6E64) : const Color(0xFFB3251E),
    );

    final baseText = ThemeData(brightness: brightness).textTheme;
    TextStyle display(TextStyle? s, FontWeight w, {double? spacing}) =>
        (s ?? const TextStyle()).copyWith(
          fontFamily: displayFamily,
          fontWeight: w,
          letterSpacing: spacing,
          color: scheme.onSurface,
        );
    final textTheme = baseText.copyWith(
      displayLarge: display(baseText.displayLarge, FontWeight.w700, spacing: -1.5),
      displayMedium: display(baseText.displayMedium, FontWeight.w700, spacing: -1),
      displaySmall: display(baseText.displaySmall, FontWeight.w700, spacing: -0.5),
      headlineLarge: display(baseText.headlineLarge, FontWeight.w700, spacing: -0.5),
      headlineMedium: display(baseText.headlineMedium, FontWeight.w700, spacing: -0.5),
      headlineSmall: display(baseText.headlineSmall, FontWeight.w600),
      titleLarge: display(baseText.titleLarge, FontWeight.w600),
      titleMedium: display(baseText.titleMedium, FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: [
        isDark ? TierColors.dark : TierColors.light,
        isDark ? MapColors.dark : MapColors.light,
      ],
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 17),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: displayFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
          foregroundColor: scheme.onSurface,
          textStyle: const TextStyle(
            fontFamily: displayFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontFamily: displayFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        textStyle: TextStyle(
          fontSize: 12,
          color: scheme.surface,
          fontWeight: FontWeight.w500,
        ),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        textStyle: TextStyle(
          fontFamily: displayFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ),
      ),
    );
  }
}
