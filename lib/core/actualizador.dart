import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'theme.dart';

/// Número de build de esta APK (lo pone GitHub Actions al compilar).
const int kBuild = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

class Actualizador {
  static bool _mostrado = false;

  /// Pregunta al servidor cuál es la última APK. Si hay una más nueva, avisa.
  static Future<void> revisar() async {
    if (_mostrado || kBuild == 0) return;
    try {
      final r = await http
          .get(Uri.parse('$kBase/app/version'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final nueva = (jsonDecode(r.body)['build'] as num?)?.toInt() ?? 0;
      final ctx = navKey.currentContext;
      if (nueva <= kBuild || ctx == null || !ctx.mounted) return;
      _mostrado = true;
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (d) => AlertDialog(
          backgroundColor: C.sup,
          title: const Text('Actualización disponible',
              style: TextStyle(color: Colors.white)),
          content: const Text(
              'Hay una versión nueva de la app. Descárgala e instálala para tener las últimas mejoras.',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Más tarde'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(d);
                await launchUrl(Uri.parse('$kBase/app/descargar'),
                    mode: LaunchMode.externalApplication);
              },
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }
}
