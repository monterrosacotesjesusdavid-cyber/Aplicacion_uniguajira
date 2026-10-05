import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tema.dart';
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

/// ¿Ya pasó la hora final de la clase? Usa la hora del celular.
bool claseTerminada(dynamic c, [DateTime? ahora]) {
  final p = hm(c['hora_fin']).split(':');
  if (p.length < 2) return false;
  final fin = (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  final n = ahora ?? DateTime.now();
  return n.hour * 60 + n.minute >= fin;
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

/// Avatar con iniciales; al tocarlo abre un panel con el nombre, el interruptor
/// de modo claro/oscuro (sol <-> luna, con onda de color) y "Cerrar sesión".
class MenuUsuario extends StatelessWidget {
  final String nombre;
  final VoidCallback onSalir;
  const MenuUsuario({super.key, required this.nombre, required this.onSalir});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Mi cuenta',
        offset: const Offset(0, 48),
        color: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        padding: EdgeInsets.zero,
        onSelected: (_) => onSalir(),
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _PanelUsuario(nombre: nombre)),
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

/// Contenido del menú del avatar. Escucha el tema para animarse en vivo.
class _PanelUsuario extends StatelessWidget {
  final String nombre;
  _PanelUsuario({required this.nombre});

  final GlobalKey _llaveInterruptor = GlobalKey();

  void _cambiarTema(BuildContext context) {
    final box = _llaveInterruptor.currentContext?.findRenderObject() as RenderBox?;
    final origen = (box != null && box.attached)
        ? box.localToGlobal(box.size.center(Offset.zero))
        : null;
    HapticFeedback.selectionClick();
    Tema.alternar(context, origen: origen);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: Tema.oscuro,
        builder: (_, osc, __) => Container(
          constraints: const BoxConstraints(minWidth: 236, maxWidth: 270),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: C.sup,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.borde),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(osc ? 0.45 : 0.14),
              blurRadius: 18, offset: const Offset(0, 6))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Nombre
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(children: [
                Container(
                  width: 34, height: 34, alignment: Alignment.center,
                  decoration: const BoxDecoration(color: C.verde, shape: BoxShape.circle),
                  child: Text(_iniciales(nombre),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5,
                      fontWeight: FontWeight.w600))),
                const SizedBox(width: 10),
                Expanded(child: Text(nombre.isEmpty ? 'Mi cuenta' : nombre,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: C.tinta, fontSize: 14.5,
                    fontWeight: FontWeight.w600))),
              ])),
            Divider(height: 1, color: C.borde),
            // Modo claro / oscuro
            InkWell(
              onTap: () => _cambiarTema(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(osc ? 'Modo oscuro' : 'Modo claro',
                      key: ValueKey<bool>(osc),
                      style: TextStyle(color: C.tinta, fontSize: 14)))),
                  _InterruptorTema(llave: _llaveInterruptor, oscuro: osc),
                ]))),
            Divider(height: 1, color: C.borde),
            // Cerrar sesión
            InkWell(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              onTap: () => Navigator.pop(context, 'salir'),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  Icon(Icons.logout_rounded, size: 18, color: C.rojo),
                  SizedBox(width: 10),
                  Text('Cerrar sesión', style: TextStyle(color: C.rojo, fontSize: 14)),
                ]))),
          ]),
        ),
      );
}

/// Interruptor en forma de píldora: el botón redondo viaja de lado a lado y su
/// icono gira y cambia entre sol (día) y luna (noche).
class _InterruptorTema extends StatelessWidget {
  final GlobalKey llave;
  final bool oscuro;
  const _InterruptorTema({required this.llave, required this.oscuro});

  @override
  Widget build(BuildContext context) {
    const dur = Duration(milliseconds: 450);
    const curva = Curves.easeInOutCubic;
    return AnimatedContainer(
      key: llave,
      duration: dur, curve: curva,
      width: 64, height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: oscuro
              ? const [Color(0xFF0B2530), Color(0xFF1B3A55)]
              : const [Color(0xFF9ED8E8), Color(0xFFD6F0F6)])),
      child: Stack(children: [
        // Estrellitas (solo de noche)
        Positioned(left: 9, top: 6, child: _estrella(oscuro, 3)),
        Positioned(left: 20, top: 16, child: _estrella(oscuro, 2)),
        Positioned(left: 13, top: 20, child: _estrella(oscuro, 2.2)),
        AnimatedAlign(
          duration: dur, curve: curva,
          alignment: oscuro ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: dur, curve: curva,
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: oscuro ? const Color(0xFFE8EEF8) : const Color(0xFFFFC53D),
              boxShadow: [BoxShadow(
                color: (oscuro ? const Color(0xFFB9C8FF) : const Color(0xFFFFB300))
                    .withOpacity(0.55),
                blurRadius: 8)]),
            child: AnimatedSwitcher(
              duration: dur,
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween<double>(begin: 0.6, end: 1.0).animate(anim),
                child: ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child))),
              child: Icon(
                oscuro ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                key: ValueKey<bool>(oscuro),
                size: 16,
                color: oscuro ? const Color(0xFF3B4A78) : Colors.white)))),
      ]),
    );
  }

  Widget _estrella(bool visible, double d) => AnimatedOpacity(
        duration: const Duration(milliseconds: 450),
        opacity: visible ? 0.9 : 0,
        child: Container(width: d, height: d,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)));
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
          decoration: BoxDecoration(border: Border(top: BorderSide(color: C.borde))),
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
          const FranjaTricolor(),
          const SizedBox(height: 10),
          Text(titulo, style: TextStyle(color: C.tinta, fontSize: 24,
            fontWeight: FontWeight.w700)),
          if (sub != null)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(sub!, style: TextStyle(color: C.suave, fontSize: 13.5))),
        ]),
      );
}

/// Bloque institucional de la pantalla "Hoy": saludo, fecha, resumen y ubicación.
/// Va a todo el ancho, en continuidad con la barra superior.
class CabeceraHoy extends StatefulWidget {
  final String resumen;
  final Widget? extra;
  const CabeceraHoy({super.key, this.resumen = '', this.extra});

  @override
  State<CabeceraHoy> createState() => _CabeceraHoyState();
}

class _CabeceraHoyState extends State<CabeceraHoy> {
  String _nombre = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final completo = (p.getString('nombre') ?? '').trim();
      if (completo.isEmpty || !mounted) return;
      final primero = completo.split(RegExp(r'\s+')).first;
      setState(() => _nombre =
          primero[0].toUpperCase() + primero.substring(1).toLowerCase());
    });
  }

  String _saludo() {
    final h = DateTime.now().hour;
    final base = h < 12 ? 'Buenos días' : h < 19 ? 'Buenas tardes' : 'Buenas noches';
    return _nombre.isEmpty ? base : '$base, $_nombre';
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat("EEEE d 'de' MMMM", 'es_CO').format(DateTime.now());
    final fecha = f.isEmpty ? f : f[0].toUpperCase() + f.substring(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
      decoration: const BoxDecoration(
        color: C.verde,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 28, height: 3,
            decoration: BoxDecoration(
              color: C.dorado, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Flexible(child: Text(_saludo(), maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withOpacity(0.85),
              fontSize: 13.5, fontWeight: FontWeight.w500))),
        ]),
        const SizedBox(height: 8),
        Text(fecha, style: const TextStyle(color: Colors.white, fontSize: 25,
          fontWeight: FontWeight.w700, height: 1.1)),
        if (widget.resumen.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4),
            child: Text(widget.resumen, style: TextStyle(
              color: Colors.white.withOpacity(0.85), fontSize: 14.5))),
        if (widget.extra != null)
          Padding(padding: const EdgeInsets.only(top: 16), child: widget.extra!),
      ]),
    );
  }
}

/// Cabecera curva compacta para pantallas internas (Horario, etc.),
/// con el mismo lenguaje visual que la de "Hoy".
class CabeceraSimple extends StatelessWidget {
  final String titulo;
  final String? sub, etiqueta;
  const CabeceraSimple({super.key, required this.titulo, this.sub, this.etiqueta});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [C.verde, Color(0xFF005D6E)]),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 28, height: 3,
              decoration: BoxDecoration(
                color: C.dorado, borderRadius: BorderRadius.circular(2))),
            if (etiqueta != null) const SizedBox(width: 8),
            if (etiqueta != null)
              Text(etiqueta!.toUpperCase(), style: TextStyle(
                color: Colors.white.withOpacity(0.85), fontSize: 11.5,
                fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 8),
          Text(titulo, style: const TextStyle(color: Colors.white,
            fontSize: 25, fontWeight: FontWeight.w700, height: 1.1)),
          if (sub != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(sub!, style: TextStyle(
              color: Colors.white.withOpacity(0.85), fontSize: 14))),
        ]),
      );
}

/// Título pequeño en mayúsculas para separar secciones.
class TituloSeccion extends StatelessWidget {
  final String texto;
  const TituloSeccion(this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Text(texto.toUpperCase(),
        style: TextStyle(color: C.suave, fontSize: 12,
          fontWeight: FontWeight.w700, letterSpacing: 0.9));
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
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: C.borde)),
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
            style: TextStyle(color: C.tinta70, fontSize: 13))),
        ]));

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: acento.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: acento.withOpacity(0.30))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(inicio, style: TextStyle(color: C.tinta, fontSize: 16.5,
                fontWeight: FontWeight.w700, height: 1.1)),
              const SizedBox(height: 3),
              Text(fin, style: TextStyle(color: C.suave, fontSize: 12)),
            ])),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(materia, style: TextStyle(color: C.tinta, fontSize: 15.5,
                  fontWeight: FontWeight.w600, height: 1.2)),
                if (_hay(persona)) _detalle(Icons.person_outline_rounded, persona!),
                // Modalidad siempre visible: virtual ya viene en `lugar`; en presencial
                // se antepone "Presencial" al salón (o se muestra sola si no hay salón).
                if (virtual)
                  _detalle(Icons.videocam_outlined, _hay(lugar) ? lugar! : 'Virtual · Meet')
                else
                  _detalle(Icons.apartment_rounded,
                    _hay(lugar) ? 'Presencial · $lugar' : 'Presencial'),
              ])),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ]),
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
          icono == Icons.check_circle_rounded
              ? CheckAnimado(color: color, size: 18)
              : Icon(icono, color: color, size: 18),
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
            trailing: Icon(Icons.chevron_right_rounded, color: C.suave)),
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
  Widget build(BuildContext context) {
    // Con una próxima clase debajo, el aviso es una línea sobria, no una pantalla vacía.
    if (extra != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: TextStyle(
            color: C.tinta, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(mensaje, style: TextStyle(color: C.suave, fontSize: 14)),
          const SizedBox(height: 16),
          extra!,
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 32, 4, 0),
      child: Column(children: [
        Icon(icono, size: 36, color: C.suave),
        const SizedBox(height: 12),
        Text(titulo, textAlign: TextAlign.center, style: TextStyle(
          color: C.tinta, fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(mensaje, textAlign: TextAlign.center,
          style: TextStyle(color: C.suave, fontSize: 14)),
      ]),
    );
  }
}

/// Busca en el horario semanal la próxima clase y la destaca con una cuenta
/// regresiva; las demás clases de ese mismo día van debajo.
/// Sirve para profesor y estudiante: ambos horarios traen `dia_num` (1 = lunes).
class ProximaClase extends StatefulWidget {
  final Future<List> Function() cargar;
  const ProximaClase({super.key, required this.cargar});
  @override
  State<ProximaClase> createState() => _ProximaClaseState();
}

class _ProximaClaseState extends State<ProximaClase> {
  List<Map> _clases = [];
  DateTime? _primera;
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
      if (mounted) {
        setState(() { _clases = delDia; _primera = primera; _cuando = cuando; });
      }
    } catch (_) {
      // Sin conexión: simplemente no se muestra la sugerencia.
    }
  }

  /// "Mañana", "En 3 días", "En 2 h 30 min".
  String _faltante(DateTime f, DateTime ahora) {
    final d0 = DateTime(ahora.year, ahora.month, ahora.day);
    final d1 = DateTime(f.year, f.month, f.day);
    final dias = d1.difference(d0).inDays;
    if (dias == 0) {
      final m = f.difference(ahora).inMinutes;
      if (m < 60) return 'En ${m < 1 ? 1 : m} min';
      final h = m ~/ 60;
      final r = m % 60;
      return r == 0 ? 'En $h h' : 'En $h h $r min';
    }
    return dias == 1 ? 'Mañana' : 'En $dias días';
  }

  @override
  Widget build(BuildContext context) {
    if (_clases.isEmpty || _primera == null) return const SizedBox.shrink();
    final c = _clases.first;
    final resto = _clases.skip(1).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Aparece(
        child: _ClaseDestacada(
          faltante: _faltante(_primera!, DateTime.now()),
          dia: kDias[_primera!.weekday],
          inicio: hm(c['hora_inicio']), fin: hm(c['hora_fin']),
          materia: (c['materia'] ?? '').toString(),
          persona: c['profesor_nombre']?.toString(),
          lugar: lugarDe(c),
          virtual: c['modalidad'] == 'virtual')),
      if (resto.isNotEmpty) ...[
        const SizedBox(height: 22),
        TituloSeccion('También $_cuando'),
        const SizedBox(height: 10),
        ...List.generate(resto.length, (i) {
          final c = resto[i];
          return Aparece(
            orden: i + 2,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Tarjeta(child: ClaseResumen(
                inicio: hm(c['hora_inicio']), fin: hm(c['hora_fin']),
                materia: (c['materia'] ?? '').toString(),
                persona: c['profesor_nombre']?.toString(),
                lugar: lugarDe(c),
                virtual: c['modalidad'] == 'virtual')),
            ));
        }),
      ],
    ]);
  }
}

/// Próxima clase: tarjeta blanca con barra de acento. Materia, horario y salón a la vista.
class _ClaseDestacada extends StatelessWidget {
  final String faltante, dia, inicio, fin, materia;
  final String? persona, lugar;
  final bool virtual;
  const _ClaseDestacada({
    required this.faltante, required this.dia, required this.inicio,
    required this.fin, required this.materia, this.persona, this.lugar,
    this.virtual = false});

  bool _hay(String? s) => s != null && s.trim().isNotEmpty;

  Widget _dato(String etiqueta, String valor, {bool tenue = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiqueta.toUpperCase(), style: TextStyle(
            color: C.suave, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.7)),
          const SizedBox(height: 4),
          Text(valor, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tenue ? C.suave : C.tinta,
              fontSize: 15.5, fontWeight: tenue ? FontWeight.w500 : FontWeight.w600,
              height: 1.2)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final salonTxt = virtual
        ? 'Virtual (Meet)'
        : (_hay(lugar) ? lugar! : 'Por confirmar');
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: C.sup,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.borde)),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: C.verde),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('PRÓXIMA CLASE · ${dia.toUpperCase()}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: C.suave, fontSize: 11.5,
                      fontWeight: FontWeight.w600, letterSpacing: 0.8))),
                  const SizedBox(width: 8),
                  Text(faltante, style: TextStyle(color: C.verdeClaro,
                    fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                Text(materia, style: TextStyle(color: C.tinta, fontSize: 20,
                  fontWeight: FontWeight.w700, height: 1.2)),
                if (_hay(persona)) Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(persona!, style: TextStyle(
                    color: C.tinta70, fontSize: 13.5))),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1, color: C.borde)),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _dato('Horario', '$inicio – $fin'),
                  const SizedBox(width: 12),
                  _dato(virtual ? 'Modalidad' : 'Salón', salonTxt,
                    tenue: !virtual && !_hay(lugar)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── ANIMACIONES SUTILES ───────────────────────────────────────────────
bool _sinAnimaciones() =>
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

/// Franja institucional: teal, dorado y rojo.
class FranjaTricolor extends StatelessWidget {
  final double ancho;
  const FranjaTricolor({super.key, this.ancho = 22});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: ancho, height: 3, child: const ColoredBox(color: C.verde)),
          SizedBox(width: ancho, height: 3, child: const ColoredBox(color: C.dorado)),
          SizedBox(width: ancho, height: 3, child: const ColoredBox(color: C.rojo)),
        ],
      );
}

/// Aparece con un fundido y un leve desplazamiento hacia arriba, una sola vez.
/// [orden] retrasa un poco cada elemento para que entren en cascada.
class Aparece extends StatefulWidget {
  final Widget child;
  final int orden;
  const Aparece({super.key, required this.child, this.orden = 0});
  @override
  State<Aparece> createState() => _ApareceState();
}

class _ApareceState extends State<Aparece> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _e =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _pos =
      Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(_e);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (_sinAnimaciones()) {
      _c.value = 1;
    } else {
      final retraso = 60 * (widget.orden < 0 ? 0 : (widget.orden > 8 ? 8 : widget.orden));
      _t = Timer(Duration(milliseconds: retraso), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _e,
        child: SlideTransition(position: _pos, child: widget.child),
      );
}

/// Recuerda qué clases terminadas ya se vieron salir hoy, para animar cada una
/// una sola vez (la primera vez que el usuario abre la app después de que acabó).
class ClasesVistas {
  static const _k = 'clases_finalizadas_vistas';
  static String _hoy() => DateFormat('yyyy-MM-dd').format(DateTime.now());
  static String clave(dynamic c) => '${_hoy()}|${c['id']}';

  static Future<Set<String>> cargar() async {
    final p = await SharedPreferences.getInstance();
    final hoy = '${_hoy()}|';
    return (p.getStringList(_k) ?? const <String>[])
        .where((e) => e.startsWith(hoy)).toSet();
  }

  static Future<void> guardar(Set<String> vistas) async {
    final p = await SharedPreferences.getInstance();
    final hoy = '${_hoy()}|';
    await p.setStringList(_k, vistas.where((e) => e.startsWith(hoy)).toList());
  }
}

/// Tarjeta de clase que, al pasar su hora final, muestra "Clase finalizada" un
/// momento y se pliega hasta desaparecer. Si la clase ya había terminado cuando
/// se abrió la pantalla, directamente no aparece.
class ClaseSaliente extends StatefulWidget {
  final bool terminada;
  final Widget child;
  final EdgeInsets padding;
  const ClaseSaliente({
    super.key, required this.terminada, required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 12)});
  @override
  State<ClaseSaliente> createState() => _ClaseSalienteState();
}

class _ClaseSalienteState extends State<ClaseSaliente>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 550));
  late final Animation<double> _vis =
      CurvedAnimation(parent: ReverseAnimation(_c), curve: Curves.easeInOut);
  late bool _oculta = widget.terminada;
  bool _aviso = false;
  Timer? _t;

  @override
  void didUpdateWidget(ClaseSaliente old) {
    super.didUpdateWidget(old);
    if (widget.terminada && !old.terminada) {
      _salir();
    } else if (!widget.terminada && old.terminada) {
      _t?.cancel();
      _c.value = 0;
      _oculta = false;
      _aviso = false;
    }
  }

  void _salir() {
    if (_sinAnimaciones()) { _oculta = true; return; }
    _aviso = true;
    _t = Timer(const Duration(milliseconds: 1600), () async {
      if (!mounted) return;
      await _c.forward();
      if (mounted) setState(() => _oculta = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_oculta) return const SizedBox.shrink();
    return SizeTransition(
      sizeFactor: _vis,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _vis,
        child: Padding(
          padding: widget.padding,
          child: Stack(children: [
            widget.child,
            if (_aviso)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 300),
                  builder: (_, t, hijo) => Opacity(opacity: t, child: hijo),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.sup.withOpacity(0.94),
                      borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      CheckAnimado(color: C.verdeClaro, size: 22),
                      const SizedBox(width: 10),
                      Text('Clase finalizada', style: TextStyle(
                        color: C.tinta, fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Número que sube desde 0 hasta [valor] al aparecer.
class ConteoAnimado extends StatelessWidget {
  final double valor;
  final String Function(double) formato;
  final TextStyle? estilo;
  const ConteoAnimado({super.key, required this.valor, required this.formato, this.estilo});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: valor),
        duration: _sinAnimaciones() ? Duration.zero : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text(formato(v), style: estilo),
      );
}

/// Círculo que crece y check que se dibuja (confirmación de asistencia).
class CheckAnimado extends StatelessWidget {
  final Color color;
  final double size;
  const CheckAnimado({super.key, required this.color, this.size = 18});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: _sinAnimaciones() ? Duration.zero : const Duration(milliseconds: 650),
        builder: (_, t, __) => CustomPaint(
          size: Size(size, size), painter: _CheckPainter(color, t)),
      );
}

class _CheckPainter extends CustomPainter {
  final Color color;
  final double t;
  _CheckPainter(this.color, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final tc = (t / 0.5).clamp(0.0, 1.0);
    canvas.drawCircle(c, r * Curves.easeOutBack.transform(tc), Paint()..color = color);

    final tk = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    if (tk <= 0) return;
    final w = size.width, h = size.height;
    final ruta = Path()
      ..moveTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.44, h * 0.67)
      ..lineTo(w * 0.73, h * 0.36);
    final m = ruta.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * Curves.easeOut.transform(tk)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_CheckPainter o) => o.t != t || o.color != color;
}
