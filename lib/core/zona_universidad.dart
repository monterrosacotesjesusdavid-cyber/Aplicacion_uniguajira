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
    Color colTitulo = C.tinta;
    bool espera = false;

    if (widget.cargando) {
      col = C.naranja; espera = true;
      titulo = 'Verificando ubicación...';
      sub = 'Obteniendo tu posición GPS';
    } else if (widget.pos == null) {
      col = C.suave; icono = Icons.location_off_rounded;
      if (GpsHelper.ubicacionFalsa) {
        titulo = 'Ubicación falsa detectada';
        sub = 'Desactiva la app de ubicación simulada';
      } else {
        titulo = 'GPS sin señal o desactivado';
        sub = 'Actívalo y desliza hacia abajo para reintentar';
      }
    } else {
      final precision = '±${widget.pos!.accuracy.toStringAsFixed(0)} m';
      final z = _zona;
      if (z == null) {
        col = C.verdeClaro;
        titulo = 'GPS activo';
        sub = 'Precisión $precision';
      } else {
        final dist = Geolocator.distanceBetween(
            widget.pos!.latitude, widget.pos!.longitude, z['lat']!, z['lon']!);
        final radio = z['radio_m']!;
        if (dist <= radio) {
          col = C.verdeClaro; icono = Icons.school_rounded;
          titulo = 'Dentro de la universidad';
          sub = 'GPS activo · precisión $precision';
        } else {
          col = C.rojo; icono = Icons.location_off_rounded;
          colTitulo = C.rojo;
          titulo = 'Fuera de la universidad';
          sub = 'A ${_distancia(max(0, dist - radio))} del campus · precisión $precision';
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: C.sup,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withOpacity(0.35)),
        boxShadow: const [
          BoxShadow(color: Color(0x1206222A), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: col.withOpacity(0.12), shape: BoxShape.circle),
          child: espera
              ? Padding(
                  padding: const EdgeInsets.all(11),
                  child: CircularProgressIndicator(strokeWidth: 2, color: col))
              : Icon(icono, size: 21, color: col),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo, style: TextStyle(color: colTitulo, fontSize: 14.5,
                  fontWeight: FontWeight.w600)),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(sub, style: const TextStyle(color: C.suave,
                      fontSize: 12.5)),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
