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
    _cargarZona();
  }

  void _cargarZona() {
    Api.zonaCampus().then((z) {
      if (mounted) setState(() { _zona = z; _zonaLista = true; });
    });
  }

  // Al refrescar la pantalla, si aún no hay zona, se vuelve a intentar.
  @override
  void didUpdateWidget(covariant ZonaUniversidadChip old) {
    super.didUpdateWidget(old);
    if (old.cargando && !widget.cargando && _zona == null) _cargarZona();
  }

  String _distancia(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    Color col;
    IconData icono;
    String txt;
    bool espera = false;

    if (_zonaLista && _zona == null) {
      // Sin datos del campus: se avisa en vez de esconder el indicador.
      col = C.suave; icono = Icons.info_outline;
      txt = Api.zonaMotivo == 'no_configurada'
          ? 'Campus sin configurar en el servidor (CAMPUS_LAT / CAMPUS_LON)'
          : 'No se pudo consultar la zona del campus. Desliza para reintentar';
    } else if (widget.cargando || !_zonaLista) {
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
