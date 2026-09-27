import 'package:flutter/material.dart';

/// Aurora Design System - Colors matching the Memento Web UI
class AuroraColors {
  // Backgrounds
  // Near-black with a faint cool cast; surfaces step up in small increments and
  // raised ones catch a hairline of light on their top edge (see GlassCard).
  static const Color bg = Color(0xFF0A0B0F);
  static const Color bg2 = Color(0xFF0E0F14);
  static const Color surface = Color(0xFF111218);
  static const Color surfaceSolid = Color(0xFF15161D);
  static const Color surfaceElevated = Color(0xFF1C1D25);

  // Borders
  static const Color border = Color(0x10FFFFFF); // rgba(255,255,255,0.06)
  static const Color borderStrong = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)
  static const Color chip = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)
  /// The lit top edge of raised surfaces.
  static const Color edgeHighlight = Color(0x1CFFFFFF); // rgba(255,255,255,0.11)

  // Accents & Brands
  static const Color accent = Color(0xFF7C84FA); // indigo, for text and icons (6:1 on bg)
  static const Color accentStrong = Color(0xFF5B63E6); // filled buttons, white text 4.8:1
  static const Color accentHover = Color(0xFF6A72F2);
  static const Color accentSoft = Color(0x247C84FA); // 14%
  static const Color onAccent = Colors.white;
  static const Color brandFrom = Color(0xFF6366F1); // Indigo
  static const Color brandTo = Color(0xFF38BDF8); // Sky

  // Foreground / Typography (never pure white: softer on near-black)
  static const Color fg1 = Color(0xFFEDEEF3);
  static const Color fg2 = Color(0xFFA4A8B6);
  static const Color fg3 = Color(0xFF767B8A); // ≥4.5:1 on bg for small text
  static const Color fg4 = Color(0xFF4F5361);
  static const Color fgBody = Color(0xFFD9DBE3); // reading text inside panels
  static const Color fgCode = Color(0xFFC9CBD6); // commands and terminal output

  // Special surfaces
  static const Color sidebar = Color(0xFF0D0E13);
  static const Color terminal = Color(0xFF07080B); // command output wells
  static const Color well = Color(0xFF0C0D11); // inset panels (diffs, previews)
  static const Color segmentSelected = Color(0xFF1F2029);
  static const Color codeText = Color(0xFFC7CAFF); // inline code on dark

  // Status (also differ in lightness, not hue alone)
  static const Color success = Color(0xFF3DD68C);
  static const Color successSoft = Color(0x1A3DD68C);
  static const Color warn = Color(0xFFF5A524);
  static const Color warnSoft = Color(0x1FF5A524);
  static const Color warnText = Color(0xFFF5B84E); // readable amber for alert copy
  static const Color danger = Color(0xFFF2555A);
  static const Color dangerSoft = Color(0x1FF2555A);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF38BDF8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassCardGradient = LinearGradient(
    colors: [
      Color(0x1FFFFFFF),
      Color(0x0AFFFFFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AuroraTheme {
  static const List<String> monospaceFontFamilyFallback = [
    'JetBrains Mono',
    'Fira Code',
    'Cascadia Code',
    'SF Mono',
    'Menlo',
    'Consolas',
    'Courier New',
    'monospace',
  ];

  static const List<String> defaultFontFamilyFallback = [
    'Inter',
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AuroraColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AuroraColors.accent,
        secondary: AuroraColors.brandFrom,
        surface: AuroraColors.surface,
        error: AuroraColors.danger,
        onPrimary: AuroraColors.onAccent,
        onSurface: AuroraColors.fg1,
      ),
      fontFamily: 'SF Pro Display',
      fontFamilyFallback: defaultFontFamilyFallback,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          color: AuroraColors.fg1,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: AuroraColors.fg2),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AuroraColors.surface,
        selectedItemColor: AuroraColors.accent,
        unselectedItemColor: AuroraColors.fg3,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AuroraColors.chip,
        hintStyle: const TextStyle(color: AuroraColors.fg3, fontSize: 13.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AuroraColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AuroraColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AuroraColors.accent, width: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AuroraColors.fg1,
          backgroundColor: const Color(0x08FFFFFF),
          side: const BorderSide(color: AuroraColors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AuroraColors.accentStrong,
          foregroundColor: AuroraColors.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AuroraColors.fg2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AuroraColors.accentStrong : const Color(0x1FFFFFFF),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AuroraColors.accentStrong,
          foregroundColor: AuroraColors.onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}
