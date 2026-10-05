import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tema.dart';

/// Paleta tomada del escudo de la Universidad de La Guajira:
/// teal, dorado y rojo sobre fondos claros.
class C {
  static const verde       = Color(0xFF00788C); // teal institucional
  static const dorado      = Color(0xFFE0A020);
  static const rojo        = Color(0xFFC0392B);
  static const naranja     = Color(0xFFC96A12);
  static const azul        = Color(0xFF1F6FA8);
  static const oscuro      = Color(0xFF06222A); // solo pantallas de cámara

  // ── Colores que cambian con el modo claro / oscuro ──
  static bool get _d => Tema.oscuro.value;
  static Color get verdeClaro  => _d ? const Color(0xFF4FC3D6) : const Color(0xFF00677A); // teal para texto/iconos
  static Color get doradoClaro => _d ? const Color(0xFFF0B94A) : const Color(0xFF8A5E00); // dorado para texto
  static Color get fondo       => _d ? const Color(0xFF0E1619) : const Color(0xFFF2F5F6);
  static Color get sup         => _d ? const Color(0xFF172126) : Colors.white;
  static Color get sup2        => _d ? const Color(0xFF1F2B31) : const Color(0xFFEBF0F2);
  static Color get borde       => _d ? const Color(0xFF2C3B42) : const Color(0xFFD3DCE0);
  static Color get suave       => _d ? const Color(0xFF93A7AE) : const Color(0xFF5F7279);
  static Color get tinta       => _d ? const Color(0xFFE6EEF0) : const Color(0xFF1C2A30);
  static Color get tinta70     => _d ? const Color(0xFFB4C4CA) : const Color(0xFF4B5C63);
}

ThemeData buildTheme() {
  OutlineInputBorder borde(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    brightness: Tema.oscuro.value ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: C.fondo,
    colorScheme: Tema.oscuro.value
      ? ColorScheme.dark(primary: C.verde, secondary: C.dorado, surface: C.sup,
          error: C.rojo, onSurface: C.tinta)
      : ColorScheme.light(primary: C.verde, secondary: C.dorado, surface: C.sup,
          error: C.rojo, onSurface: C.tinta),
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
        side: BorderSide(color: C.borde),
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
        foregroundColor: C.tinta, side: BorderSide(color: C.borde),
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
      labelStyle: TextStyle(color: C.suave, fontSize: 12),
      hintStyle: TextStyle(color: C.suave.withOpacity(0.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: C.sup, selectedItemColor: C.verde,
      unselectedItemColor: C.suave, type: BottomNavigationBarType.fixed, elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tema.oscuro.value ? C.sup2 : C.tinta,
      contentTextStyle: TextStyle(color: Tema.oscuro.value ? C.tinta : Colors.white),
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
