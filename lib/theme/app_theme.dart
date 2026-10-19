import 'package:flutter/material.dart';

import '../logic/risk_assessment.dart';

class AppColors {
  static const brandDark = Color(0xFF1B5E20);
  static const brand = Color(0xFF2E7D32);
  static const brandLight = Color(0xFF43A047);
  static const background = Color(0xFFF4F7F4);
  static const ink = Color(0xFF1C2B1E);
  static const muted = Color(0xFF5F6F62);
  static const border = Color(0xFFE1E8E2);
}

/// Cor de cada nível de risco. Usada em chips, cartões e no mapa.
Color levelColor(RiskLevel level) => switch (level) {
      RiskLevel.low => const Color(0xFF2E7D32),
      RiskLevel.moderate => const Color(0xFFB7791F),
      RiskLevel.high => const Color(0xFFE65100),
      RiskLevel.emergency => const Color(0xFFC62828),
    };

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
