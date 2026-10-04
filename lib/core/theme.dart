import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paleta tomada del escudo de la Universidad de La Guajira:
/// teal, dorado y rojo sobre fondos claros.
class C {
  static const verde       = Color(0xFF00788C); // teal institucional
  static const verdeClaro  = Color(0xFF00677A); // teal para texto e iconos sobre blanco
  static const dorado      = Color(0xFFE0A020);
  static const doradoClaro = Color(0xFF8A5E00); // dorado oscuro para texto sobre blanco
  static const rojo        = Color(0xFFC0392B);
  static const naranja     = Color(0xFFC96A12);
  static const azul        = Color(0xFF1F6FA8);

  static const oscuro      = Color(0xFF06222A); // solo pantallas de cámara
  static const fondo       = Color(0xFFF2F5F6);
  static const sup         = Colors.white;
  static const sup2        = Color(0xFFEBF0F2);
  static const borde       = Color(0xFFD3DCE0);
  static const suave       = Color(0xFF5F7279);
  static const tinta       = Color(0xFF1C2A30);
  static const tinta70     = Color(0xFF4B5C63);
}

ThemeData buildTheme() {
  OutlineInputBorder borde(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    // Fuente incluida dentro de la app (assets/fonts): se ve igual con o sin internet.
    fontFamily: 'PlusJakartaSans',
    scaffoldBackgroundColor: C.fondo,
    colorScheme: const ColorScheme.light(
      primary: C.verde, secondary: C.dorado, surface: C.sup,
      error: C.rojo, onSurface: C.tinta,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.verde, foregroundColor: Colors.white, elevation: 0,
      scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: C.sup, elevation: 0, margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: C.borde),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: C.verde, foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.tinta, side: const BorderSide(color: C.borde),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: C.sup,
      border: borde(C.borde),
      enabledBorder: borde(C.borde),
      focusedBorder: borde(C.verde, 1.5),
      errorBorder: borde(C.rojo),
      focusedErrorBorder: borde(C.rojo, 1.5),
      labelStyle: const TextStyle(color: C.suave, fontSize: 12),
      hintStyle: TextStyle(color: C.suave.withOpacity(0.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: C.sup, selectedItemColor: C.verde,
      unselectedItemColor: C.suave, type: BottomNavigationBarType.fixed, elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.tinta, contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.sup, surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerColor: C.borde,
  );
}
