import 'package:flutter/material.dart';
import '../screens/admin/admin_home.dart';
import '../screens/auth/enrolar_rostro_screen.dart';
import '../screens/estudiante/estudiante_home.dart';
import '../screens/profesor/profesor_home.dart';

/// Pantalla de inicio según rol. Si es estudiante/profesor y aún no registró su
/// rostro, primero pasa por el registro facial.
Widget destinoPorRol(String rol, {bool rostroRegistrado = true}) {
  final Widget home = rol == 'admin'
      ? const AdminHome()
      : rol == 'profesor' ? const ProfesorHome() : const EstudianteHome();
  if (rol == 'admin' || rostroRegistrado) return home;
  return EnrolarRostroScreen(destino: home);
}
