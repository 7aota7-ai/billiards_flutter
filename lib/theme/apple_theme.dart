import 'dart:ui';

import 'package:flutter/material.dart';

/// Apple Japan（Apple_DESIGN.md）のトークンと Theme。
abstract final class AppleColors {
  static const Color nearBlack = Color(0xFF1D1D1F);
  static const Color pureBlack = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lightGray = Color(0xFFF5F5F7);
  static const Color appleBlue = Color(0xFF0071E3);
  static const Color linkBlue = Color(0xFF0066CC);
  static const Color brightBlue = Color(0xFF2997FF);
  static const Color glyphGraySecondary = Color(0xFF6E6E73);

  /// Primary text（#1d1d1f / 実質 ~0.88）
  static const Color textPrimary = nearBlack;

  /// Secondary（rgba(0,0,0,0.56)）
  static const Color textSecondary = Color(0x8F000000);

  /// On dark
  static const Color textOnDark = Color(0xFFF5F5F7);

  static const Color navGlass = Color(0xCC000000);
  static const Color focusRing = Color(0x330071E3);

  /// カード影（設定・スコアボード共通。強すぎない程度）
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0x12000000),
      offset: const Offset(0, 2),
      blurRadius: 10,
      spreadRadius: 0,
    ),
  ];

  static const Color separator = Color(0xFFD2D2D7);

  /// iOS システム色に近いアクセント（試合 UI の状態表示用）
  static const Color systemGreen = Color(0xFF34C759);
  static const Color systemRed = Color(0xFFFF3B30);
  static const Color systemOrange = Color(0xFFFF9500);
}

/// SF Pro は同梱しない。日本語は Meiryo / Yu Gothic を優先（Windows）。
const String kAppleFontFamily = 'Meiryo UI';
const List<String> kAppleFontFallback = [
  'Meiryo',
  'Yu Gothic UI',
  'Segoe UI',
  'Hiragino Sans',
  'Helvetica Neue',
  'Arial',
  'sans-serif',
];

TextTheme _buildAppleTextTheme(ColorScheme cs) {
  const bodyHeight = 1.47;
  const bodySpacing = -0.357;

  return TextTheme(
    displayLarge: TextStyle(
      fontFamily: kAppleFontFamily,
      fontFamilyFallback: kAppleFontFallback,
      fontSize: 56,
      fontWeight: FontWeight.w600,
      height: 1.05,
      letterSpacing: -0.5,
      color: AppleColors.textPrimary,
    ),
    displayMedium: TextStyle(
      fontFamily: kAppleFontFamily,
      fontFamilyFallback: kAppleFontFallback,
      fontSize: 56,
      fontWeight: FontWeight.w500,
      height: 1.05,
      letterSpacing: 2,
      color: AppleColors.textPrimary,
    ),
    headlineMedium: TextStyle(
      fontFamily: kAppleFontFamily,
      fontFamilyFallback: kAppleFontFallback,
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.18,
      letterSpacing: 0.196,
      color: AppleColors.textPrimary,
    ),
    titleLarge: TextStyle(
      fontFamily: kAppleFontFamily,
      fontFamilyFallback: kAppleFontFallback,
      fontSize: 21,
      fontWeight: FontWeight.w600,
      height: 1.24,
      letterSpacing: 0.231,
      color: AppleColors.textPrimary,
    ),
    titleMedium: TextStyle(
      fontFamily: kAppleFontFamily,
      fontFamilyFallback: kAppleFontFallback,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: bodyHeight,
      letterSpacing: bodySpacing,
      color: AppleColors.textPrimary,
    ),
    bodyLarge: TextStyle(
      fontFamily: kAppleFontFamily,
      fontFamilyFallback: kAppleFontFallback,
      fontSize: 17,
      fontWeight: FontWeight.w400,
      height: bodyHeight,
      letterSpacing: bodySpacing,
      color: AppleColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontFamily: kAppleFontFamily,
      fontFamilyFallback: kAppleFontFallback,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.47,
      letterSpacing: 0,
      color: AppleColors.textPrimary,
    ),
    labelLarge: TextStyle(
      fontFamily: kAppleFontFamily,
      fontFamilyFallback: kAppleFontFallback,
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.0,
      letterSpacing: 0,
      color: AppleColors.textSecondary,
    ),
  );
}

ThemeData buildAppleTheme() {
  final base = ColorScheme.light(
    primary: AppleColors.appleBlue,
    onPrimary: AppleColors.white,
    secondary: AppleColors.linkBlue,
    onSecondary: AppleColors.white,
    surface: AppleColors.white,
    onSurface: AppleColors.textPrimary,
    error: const Color(0xFFE30000),
    onError: AppleColors.white,
  );

  final textTheme = _buildAppleTextTheme(base);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: base,
    scaffoldBackgroundColor: AppleColors.lightGray,
    fontFamily: kAppleFontFamily,
    fontFamilyFallback: kAppleFontFallback,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: AppleColors.textOnDark,
      titleTextStyle: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppleColors.textOnDark,
        letterSpacing: -0.2,
      ),
      iconTheme: const IconThemeData(color: AppleColors.textOnDark),
    ),
    cardTheme: CardThemeData(
      color: AppleColors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppleColors.separator.withValues(alpha: 0.6)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppleColors.separator,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppleColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppleColors.separator),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppleColors.separator),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppleColors.appleBlue, width: 2),
      ),
      hintStyle:
          textTheme.bodyLarge?.copyWith(color: AppleColors.textSecondary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppleColors.appleBlue,
        foregroundColor: AppleColors.white,
        disabledBackgroundColor: AppleColors.appleBlue.withValues(alpha: 0.35),
        disabledForegroundColor: AppleColors.white.withValues(alpha: 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        textStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w400,
          letterSpacing: -0.2,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppleColors.appleBlue,
        side: const BorderSide(color: AppleColors.appleBlue, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        textStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w400,
          letterSpacing: -0.2,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppleColors.linkBlue,
        textStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w400,
          letterSpacing: -0.2,
        ),
      ),
    ),
  );
}

/// グローバルナビ風: すりガラス + 高さ 44（`--r-globalnav-height`）
PreferredSizeWidget buildAppleGlassAppBar(
  BuildContext context, {
  required String title,
  Widget? leading,
  List<Widget>? actions,
  bool centerTitle = true,
}) {
  final titleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppleColors.textOnDark,
        letterSpacing: -0.3,
        height: 1.35,
      );

  return AppBar(
    toolbarHeight: 44,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: centerTitle,
    backgroundColor: Colors.transparent,
    foregroundColor: AppleColors.textOnDark,
    leading: leading,
    actions: actions,
    title: Text(title, style: titleStyle),
    flexibleSpace: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(color: AppleColors.navGlass),
        ),
      ),
    ),
  );
}

/// コンテンツ最大幅（1260px）
class AppleContentWidth extends StatelessWidget {
  const AppleContentWidth({super.key, required this.child});

  final Widget child;

  static const double maxWidth = 1260;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 白カード + Apple 影
class AppleCard extends StatelessWidget {
  const AppleCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppleColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppleColors.cardShadow,
        border: Border.all(
          color: borderColor ?? AppleColors.separator.withValues(alpha: 0.35),
          width: borderWidth,
        ),
      ),
      padding: padding ?? const EdgeInsets.all(20),
      child: child,
    );
  }
}
