import 'package:flutter/material.dart';

/// Trust-tier colors used by the treemap, badges, and insights.
/// Values validated for CVD separation and surface contrast in both modes;
/// `protected` is deliberately gray (recessive) and always pairs with a lock
/// icon so meaning is never carried by color alone.
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
    safe: Color(0xFF1BAF7A),
    review: Color(0xFFEDA100),
    protected: Color(0xFF898781),
  );

  static const dark = TierColors(
    safe: Color(0xFF199E70),
    review: Color(0xFFC98500),
    protected: Color(0xFF898781),
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

extension TierColorsX on ThemeData {
  TierColors get tiers => extension<TierColors>()!;
}

/// Central theme. Both modes derive from one teal seed so every surface and
/// accent stays in the same family.
abstract final class CleanMindTheme {
  static const _seed = Color(0xFF00897B);

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [
        brightness == Brightness.light ? TierColors.light : TierColors.dark,
      ],
      scaffoldBackgroundColor:
          brightness == Brightness.light ? scheme.surface : null,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
