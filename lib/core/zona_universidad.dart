import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'api.dart';
import 'gps_helper.dart';
import 'theme.dart';

/// Un solo indicador de ubicación: estado del GPS + si el usuario está dentro
/// o fuera de la universidad. Las coordenadas del campus las entrega el
/// servidor y quedan guardadas en el celular (funciona sin internet).
/// Si el campus no está configurado, muestra solo el estado del GPS.
class UbicacionChip extends StatefulWidget {
  final Position? pos;
  final bool cargando;
  const UbicacionChip({super.key, required this.pos, required this.cargando});

  @override
  State<UbicacionChip> createState() => _UbicacionChipState();
}

class _UbicacionChipState extends State<UbicacionChip> {
  Map<String, double>? _zona;

  @override
  void initState() {
    super.initState();
    _cargarZona();
  }

  void _cargarZona() {
    Api.zonaCampus().then((z) {
      if (mounted) setState(() => _zona = z);
    });
  }

  // Al refrescar la pantalla, si aún no hay zona, se vuelve a intentar.
  @override
  void didUpdateWidget(covariant UbicacionChip old) {
    super.didUpdateWidget(old);
    if (old.cargando && !widget.cargando && _zona == null) _cargarZona();
  }

  String _distancia(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    Color col;
    IconData icono = Icons.my_location;
    String titulo;
    String? sub;
    bool espera = false;

    if (widget.cargando) {
      col = C.naranja; espera = true;
      titulo = 'Verificando ubicación...';
    } else if (widget.pos == null) {
      col = C.suave; icono = Icons.location_off;
      if (GpsHelper.ubicacionFalsa) {
        titulo = 'Ubicación falsa detectada';
        sub = 'Desactiva la app de ubicación simulada';
      } else {
        titulo = 'GPS sin señal o desactivado';
        sub = 'Actívalo y desliza para reintentar';
      }
    } else {
      final precision = '±${widget.pos!.accuracy.toStringAsFixed(0)} m';
      final z = _zona;
      if (z == null) {
        col = C.verdeClaro;
        titulo = 'GPS activo';
        sub = precision;
      } else {
        final dist = Geolocator.distanceBetween(
            widget.pos!.latitude, widget.pos!.longitude, z['lat']!, z['lon']!);
        final radio = z['radio_m']!;
        if (dist <= radio) {
          col = C.verdeClaro; icono = Icons.school;
          titulo = 'Dentro de la universidad';
          sub = 'GPS activo · $precision';
        } else {
          col = C.rojo; icono = Icons.location_off;
          titulo = 'Fuera de la universidad';
          sub = 'A ${_distancia(max(0, dist - radio))} · GPS activo · $precision';
        }
      }
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: col.withOpacity(0.10), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          espera
              ? SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: col))
              : Icon(icono, size: 18, color: col),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titulo, style: TextStyle(color: col, fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
                if (sub != null)
                  Text(sub, style: TextStyle(color: col.withOpacity(0.8),
                      fontSize: 11.5)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
