import 'package:geolocator/geolocator.dart';

class GpsHelper {
  /// true si la última lectura venía de una app de ubicación falsa.
  static bool ubicacionFalsa = false;

  static Future<Position?> obtenerPosicion() async {
    ubicacionFalsa = false;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (pos.isMocked) {
        ubicacionFalsa = true;
        return null;
      }
      return pos;
    } catch (_) {
      return null;
    }
  }

  static String get mensajeError => ubicacionFalsa
      ? 'Desactiva la ubicación falsa para poder firmar'
      : 'Activa el GPS para registrar asistencia';
}
