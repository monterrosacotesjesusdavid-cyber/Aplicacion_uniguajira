import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'api.dart';
import 'gps_helper.dart';
import 'theme.dart';

/// Indica si el usuario está dentro o fuera del campus de la universidad.
/// Las coordenadas del campus las entrega el servidor y quedan guardadas en el
/// celular, así que también funciona sin internet. Si el campus no está
/// configurado en el servidor, no muestra nada.
class ZonaUniversidadChip extends StatefulWidget {
  final Position? pos;
  final bool cargando;
  const ZonaUniversidadChip({super.key, required this.pos, required this.cargando});

  @override
  State<ZonaUniversidadChip> createState() => _ZonaUniversidadChipState();
}

class _ZonaUniversidadChipState extends State<ZonaUniversidadChip> {
  Map<String, double>? _zona;
  bool _zonaLista = false;

  @override
  void initState() {
    super.initState();
    Api.zonaCampus().then((z) {
      if (mounted) setState(() { _zona = z; _zonaLista = true; });
    });
  }

  String _distancia(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    // Campus no configurado: no hay nada que mostrar.
    if (_zonaLista && _zona == null) return const SizedBox.shrink();

    Color col;
    IconData icono;
    String txt;
    bool espera = false;

    if (widget.cargando || !_zonaLista) {
      col = C.naranja; icono = Icons.school_outlined; espera = true;
      txt = 'Verificando si estás en la universidad...';
    } else if (widget.pos == null) {
      col = C.suave; icono = Icons.location_off;
      txt = GpsHelper.ubicacionFalsa
          ? 'Ubicación falsa detectada'
          : 'Sin ubicación: no se puede saber si estás en la universidad';
    } else {
      final z = _zona!;
      final dist = Geolocator.distanceBetween(
          widget.pos!.latitude, widget.pos!.longitude, z['lat']!, z['lon']!);
      final radio = z['radio_m']!;
      if (dist <= radio) {
        col = C.verdeClaro; icono = Icons.school;
        txt = 'Dentro de la universidad';
      } else {
        col = C.rojo; icono = Icons.location_off;
        txt = 'Fuera de la universidad · a ${_distancia(max(0, dist - radio))}';
      }
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: col.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          espera
              ? SizedBox(width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: col))
              : Icon(icono, size: 14, color: col),
          const SizedBox(width: 7),
          Flexible(child: Text(txt, style: TextStyle(color: col, fontSize: 12.5,
              fontWeight: FontWeight.w500))),
        ]),
      ),
    );
  }
}
