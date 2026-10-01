import 'package:flutter/material.dart';

class C {
  static const verde       = Color(0xFF00899D);
  static const verdeClaro  = Color(0xFF00A0B8);
  static const dorado      = Color(0xFFF0A828);
  static const doradoClaro = Color(0xFFF6C467);
  static const oscuro      = Color(0xFF06222A);
  static const sup         = Color(0xFF0C323C);
  static const sup2        = Color(0xFF124150);
  static const borde       = Color(0xFF1B4F5F);
  static const suave       = Color(0xFF7FA9B4);
  static const rojo        = Color(0xFFE05048);
  static const naranja     = Color(0xFFE67E22);
  static const azul        = Color(0xFF2980B9);
}

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: C.oscuro,
  colorScheme: const ColorScheme.dark(
    primary: C.verde, secondary: C.dorado, surface: C.sup, error: C.rojo,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: C.oscuro, foregroundColor: Colors.white, elevation: 0,
    titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
  ),
  cardTheme: CardThemeData(
    color: C.sup, elevation: 0, margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: C.borde),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: C.verde, foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      elevation: 0,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true, fillColor: C.sup2,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: C.borde)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: C.borde)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: C.verdeClaro, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: C.rojo)),
    labelStyle: const TextStyle(color: C.suave, fontSize: 12),
    hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: C.sup, selectedItemColor: C.verdeClaro,
    unselectedItemColor: C.suave, type: BottomNavigationBarType.fixed, elevation: 0,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: C.sup2, contentTextStyle: const TextStyle(color: Colors.white),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    behavior: SnackBarBehavior.floating,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: C.sup,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
);
