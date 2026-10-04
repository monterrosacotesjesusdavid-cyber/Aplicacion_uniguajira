import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'theme.dart';

/// Piezas visuales compartidas por el portal docente y el estudiantil.
/// Si cambias algo aquí, cambian los dos portales a la vez.

const kDias = [
  '', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
];

/// "07:00:00" -> "07:00"
String hm(dynamic h) {
  final s = (h ?? '').toString();
  return s.length >= 5 ? s.substring(0, 5) : s;
}

/// Texto de ubicación de una clase (salón y bloque, o Meet si es virtual).
String lugarDe(dynamic c) {
  if (c['modalidad'] == 'virtual') return 'Clase virtual (Meet)';
  return [c['salon'], c['bloque']]
      .where((e) => e != null && e.toString().trim().isNotEmpty)
      .join(', ');
}

String _iniciales(String nombre) {
  final p = nombre.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  if (p.length == 1) return p[0][0].toUpperCase();
  return (p[0][0] + p[1][0]).toUpperCase();
}

/// Botón principal con el mismo estilo en toda la app.
ButtonStyle estiloBoton({Color? fondo, double alto = 46, bool ancho = true}) =>
    ElevatedButton.styleFrom(
      backgroundColor: fondo ?? C.verde,
      disabledBackgroundColor: C.borde,
      minimumSize: Size(ancho ? double.infinity : 0, alto),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

// ── BARRA SUPERIOR ────────────────────────────────────────────────────
class MarcaAppBar extends StatelessWidget {
  final String sub;
  const MarcaAppBar({super.key, required this.sub});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 40, height: 40, padding: const EdgeInsets.all(5),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Image.asset('assets/escudo.png', fit: BoxFit.contain)),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('UniGuajira',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
                height: 1.1)),
            const SizedBox(height: 1),
            Text(sub, style: TextStyle(fontSize: 11.5,
              color: Colors.white.withOpacity(0.8))),
          ]),
      ]);
}

/// Avatar con iniciales; al tocarlo muestra el nombre y "Cerrar sesión".
class MenuUsuario extends StatelessWidget {
  final String nombre;
  final VoidCallback onSalir;
  const MenuUsuario({super.key, required this.nombre, required this.onSalir});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Mi cuenta',
        offset: const Offset(0, 48),
        color: C.sup,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (_) => onSalir(),
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            enabled: false,
            child: Text(nombre.isEmpty ? 'Mi cuenta' : nombre,
              style: const TextStyle(color: C.tinta, fontWeight: FontWeight.w600))),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'salir',
            child: Row(children: [
              Icon(Icons.logout_rounded, size: 18, color: C.rojo),
              SizedBox(width: 10),
              Text('Cerrar sesión', style: TextStyle(color: C.rojo)),
            ])),
        ],
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 16),
          child: Container(
            width: 36, height: 36, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.55))),
            child: Text(_iniciales(nombre),
              style: const TextStyle(color: Colors.white, fontSize: 12.5,
                fontWeight: FontWeight.w600)))),
      );
}

// ── BARRA INFERIOR ────────────────────────────────────────────────────
class BarraInferior extends StatelessWidget {
  final int indice;
  final ValueChanged<int> onTap;
  const BarraInferior({super.key, required this.indice, required this.onTap});

  @override
  Widget build(BuildContext context) => NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: C.sup,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 66,
          indicatorColor: C.verde.withOpacity(0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? C.verdeClaro : C.suave)),
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? C.verdeClaro : C.suave)),
        ),
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.borde))),
          child: NavigationBar(
            selectedIndex: indice,
            onDestinationSelected: onTap,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today_rounded), label: 'Hoy'),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month_rounded), label: 'Horario'),
            ],
          ),
        ),
      );
}

// ── ENCABEZADOS ───────────────────────────────────────────────────────
class TituloPantalla extends StatelessWidget {
  final String titulo;
  final String? sub;
  const TituloPantalla({super.key, required this.titulo, this.sub});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(color: C.tinta, fontSize: 22,
            fontWeight: FontWeight.w600)),
          if (sub != null)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(sub!, style: const TextStyle(color: C.suave, fontSize: 13.5))),
        ]),
      );
}

/// Fecha de hoy, con un resumen opcional ("Tienes 2 clases hoy") y un extra (GPS).
class CabeceraHoy extends StatelessWidget {
  final String resumen;
  final Widget? extra;
  const CabeceraHoy({super.key, this.resumen = '', this.extra});

  @override
  Widget build(BuildContext context) {
    final f = DateFormat("EEEE d 'de' MMMM", 'es_CO').format(DateTime.now());
    final fecha = f.isEmpty ? f : f[0].toUpperCase() + f.substring(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fecha, style: const TextStyle(color: C.tinta, fontSize: 22,
          fontWeight: FontWeight.w600)),
        if (resumen.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 2),
            child: Text(resumen, style: const TextStyle(color: C.suave,
              fontSize: 14))),
        if (extra != null)
          Padding(padding: const EdgeInsets.only(top: 14), child: extra!),
      ]),
    );
  }
}

class GpsChip extends StatelessWidget {
  final bool cargando, ok;
  final String textoOk;
  const GpsChip({super.key, required this.cargando, required this.ok, required this.textoOk});

  @override
  Widget build(BuildContext context) {
    final col = cargando ? C.naranja : ok ? C.verdeClaro : C.rojo;
    final txt = cargando ? 'Obteniendo ubicación...'
        : ok ? textoOk : 'GPS no disponible, actívalo para firmar';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: col.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          cargando
            ? SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: col))
            : Icon(ok ? Icons.gps_fixed : Icons.gps_off, size: 14, color: col),
          const SizedBox(width: 7),
          Flexible(child: Text(txt, style: TextStyle(color: col, fontSize: 12.5,
            fontWeight: FontWeight.w500))),
        ]),
      ),
    );
  }
}

// ── TARJETAS ──────────────────────────────────────────────────────────
class Tarjeta extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Tarjeta({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        elevation: 1.5,
        shadowColor: const Color(0x2606222A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: C.borde)),
        child: onTap == null ? child : InkWell(onTap: onTap, child: child),
      );
}

/// Hora grande a la izquierda, barra de color y datos de la clase.
class ClaseResumen extends StatelessWidget {
  final String inicio, fin, materia;
  final String? lugar, persona;
  final bool virtual;
  final Color acento;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const ClaseResumen({
    super.key, required this.inicio, required this.fin, required this.materia,
    this.lugar, this.persona, this.virtual = false, this.acento = C.verde,
    this.trailing, this.padding = const EdgeInsets.all(16),
  });

  bool _hay(String? s) => s != null && s.trim().isNotEmpty;

  Widget _detalle(IconData icono, String texto) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Icon(icono, size: 15, color: C.suave),
          const SizedBox(width: 6),
          Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: C.tinta70, fontSize: 13))),
        ]));

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inicio, style: const TextStyle(color: C.tinta, fontSize: 17,
                    fontWeight: FontWeight.w600, height: 1.1)),
                  const SizedBox(height: 2),
                  Text(fin, style: const TextStyle(color: C.suave, fontSize: 12.5)),
                ])),
            Container(width: 4,
              decoration: BoxDecoration(color: acento, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(materia, style: const TextStyle(color: C.tinta, fontSize: 15,
                    fontWeight: FontWeight.w600, height: 1.2)),
                  if (_hay(persona)) _detalle(Icons.person_outline_rounded, persona!),
                  if (_hay(lugar))
                    _detalle(virtual ? Icons.videocam_outlined : Icons.place_outlined, lugar!),
                ])),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Center(child: trailing!),
            ],
          ]),
        ),
      );
}

/// Mensaje de estado dentro de una tarjeta (registrado, pendiente, etc.).
class AvisoEstado extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;
  const AvisoEstado({super.key, required this.icono, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icono, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: TextStyle(color: color, fontSize: 12.5,
            fontWeight: FontWeight.w500))),
        ]),
      );
}

class Pastilla extends StatelessWidget {
  final String texto;
  final Color color;
  const Pastilla({super.key, required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 11.5,
          fontWeight: FontWeight.w600)),
      );
}

// ── HORARIO SEMANAL ───────────────────────────────────────────────────
class EncabezadoDia extends StatelessWidget {
  final String dia;
  final bool esHoy;
  const EncabezadoDia({super.key, required this.dia, required this.esHoy});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Row(children: [
          Text(dia, style: TextStyle(
            color: esHoy ? C.verdeClaro : C.tinta, fontSize: 15,
            fontWeight: FontWeight.w600)),
          if (esHoy) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: C.verde, borderRadius: BorderRadius.circular(10)),
              child: const Text('Hoy', style: TextStyle(color: Colors.white,
                fontSize: 11, fontWeight: FontWeight.w600))),
          ],
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: C.borde)),
        ]),
      );
}

class TarjetaHorario extends StatelessWidget {
  final String inicio, fin, materia;
  final String? lugar, persona;
  final bool virtual, esHoy;
  final VoidCallback onTap;
  const TarjetaHorario({
    super.key, required this.inicio, required this.fin, required this.materia,
    required this.onTap, this.lugar, this.persona,
    this.virtual = false, this.esHoy = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Tarjeta(
          onTap: onTap,
          child: ClaseResumen(
            inicio: inicio, fin: fin, materia: materia,
            lugar: lugar, persona: persona, virtual: virtual,
            acento: esHoy ? C.verde : C.suave.withOpacity(0.35),
            padding: const EdgeInsets.all(14),
            trailing: const Icon(Icons.chevron_right_rounded, color: C.suave)),
        ),
      );
}

// ── ESTADO VACÍO Y PRÓXIMA CLASE ──────────────────────────────────────
class EstadoVacio extends StatelessWidget {
  final String titulo, mensaje;
  final IconData icono;
  final Widget? extra;
  const EstadoVacio({super.key, required this.titulo, required this.mensaje,
    this.icono = Icons.event_available_rounded, this.extra});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 28, 4, 8),
        child: Column(children: [
          Container(
            width: 76, height: 76,
            decoration: BoxDecoration(
              color: C.verde.withOpacity(0.10), shape: BoxShape.circle),
            child: Icon(icono, size: 34, color: C.verdeClaro)),
          const SizedBox(height: 16),
          Text(titulo, textAlign: TextAlign.center, style: const TextStyle(
            color: C.tinta, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(mensaje, textAlign: TextAlign.center,
            style: const TextStyle(color: C.suave, fontSize: 14)),
          if (extra != null) ...[const SizedBox(height: 28), extra!],
        ]),
      );
}

/// Busca en el horario semanal el próximo día con clases y las muestra todas.
/// Sirve para profesor y estudiante: ambos horarios traen `dia_num` (1 = lunes).
class ProximaClase extends StatefulWidget {
  final Future<List> Function() cargar;
  const ProximaClase({super.key, required this.cargar});
  @override
  State<ProximaClase> createState() => _ProximaClaseState();
}

class _ProximaClaseState extends State<ProximaClase> {
  List<Map> _clases = [];
  String _cuando = '';

  @override
  void initState() { super.initState(); _buscar(); }

  /// Fecha y hora de la próxima vez que ocurre esta clase.
  DateTime? _proximaFecha(Map c, DateTime ahora) {
    final dia = c['dia_num'];
    if (dia is! num) return null;
    final p = hm(c['hora_inicio']).split(':');
    if (p.length < 2) return null;
    final hh = int.tryParse(p[0]);
    final mm = int.tryParse(p[1]);
    if (hh == null || mm == null) return null;
    var f = DateTime(ahora.year, ahora.month, ahora.day, hh, mm)
        .add(Duration(days: (dia.toInt() - ahora.weekday + 7) % 7));
    if (!f.isAfter(ahora)) f = f.add(const Duration(days: 7));
    return f;
  }

  Future<void> _buscar() async {
    try {
      final horario = await widget.cargar();
      final ahora = DateTime.now();
      final items = <MapEntry<DateTime, Map>>[];
      for (final c in horario) {
        final f = _proximaFecha(Map.from(c), ahora);
        if (f != null) items.add(MapEntry(f, Map.from(c)));
      }
      if (items.isEmpty) return;
      items.sort((a, b) => a.key.compareTo(b.key));
      final primera = items.first.key;
      final dia0 = DateTime(primera.year, primera.month, primera.day);
      // Todas las clases de ese mismo día, en orden de hora.
      final delDia = items
          .where((e) => DateTime(e.key.year, e.key.month, e.key.day) == dia0)
          .map((e) => e.value)
          .toList();
      final cuando = 'el ${kDias[primera.weekday].toLowerCase()}';
      if (mounted) setState(() { _clases = delDia; _cuando = cuando; });
    } catch (_) {
      // Sin conexión: simplemente no se muestra la sugerencia.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_clases.isEmpty) return const SizedBox.shrink();
    final plural = _clases.length > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.event_outlined, size: 18, color: C.verdeClaro),
        const SizedBox(width: 8),
        Expanded(child: Text(
          plural ? 'Tus próximas clases para $_cuando' : 'Tu próxima clase para $_cuando',
          style: const TextStyle(color: C.tinta, fontSize: 14.5,
            fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 10),
      ..._clases.map((c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Tarjeta(child: ClaseResumen(
          inicio: hm(c['hora_inicio']), fin: hm(c['hora_fin']),
          materia: (c['materia'] ?? '').toString(),
          persona: c['profesor_nombre']?.toString(),
          lugar: lugarDe(c),
          virtual: c['modalidad'] == 'virtual')),
      )),
    ]);
  }
}
