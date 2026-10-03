import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/api.dart';

/// Clase virtual (Meet): el profesor llama a lista y marca quién estuvo.
/// Puede corregir hasta 24 h después de terminada la clase; luego solo el admin.
/// El admin usa esta misma pantalla (admin: true) para corregir y ver el historial.
class ListaVirtualScreen extends StatefulWidget {
  final int horarioId;
  final String materia;
  final bool admin;
  final String? fecha; // solo la usa el admin (yyyy-MM-dd)
  const ListaVirtualScreen({
    super.key,
    required this.horarioId,
    required this.materia,
    this.admin = false,
    this.fecha,
  });
  @override
  State<ListaVirtualScreen> createState() => _ListaVirtualState();
}

class _ListaVirtualState extends State<ListaVirtualScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _guardando = false;
  String? _error;
  final _link = TextEditingController();
  final Set<int> _ocupados = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _load({bool silencioso = false}) async {
    if (!silencioso) setState(() { _loading = true; _error = null; });
    try {
      final d = await Api.listaVirtual(widget.horarioId,
          admin: widget.admin, fecha: widget.fecha);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
        final l = ((d['clase'] ?? {}) as Map)['link']?.toString() ?? '';
        if (_link.text.isEmpty) _link.text = l;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_data == null) {
          _error = e is String ? e : 'No se pudo cargar la lista. Revisa tu conexión.';
        }
      });
    }
  }

  Map<String, dynamic> get _clase =>
      Map<String, dynamic>.from((_data?['clase'] ?? {}) as Map);

  List<Map<String, dynamic>> get _ests => ((_data?['estudiantes'] ?? []) as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  bool get _editableTiempo => _data?['editable'] == true;
  bool get _firmo => _clase['profesor_firmo'] == true;
  bool get _puedeEditar => widget.admin || (_editableTiempo && _firmo);

  void _snack(String msg, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: error ? C.rojo : C.verde));

  Future<void> _marcar(List<int> ids, bool presente) async {
    if (ids.isEmpty || !_puedeEditar) return;
    setState(() => _ocupados.addAll(ids));
    try {
      final r = await Api.marcarVirtual(widget.horarioId, ids, presente,
          admin: widget.admin, fecha: widget.fecha ?? _data?['fecha']?.toString());
      if (!mounted) return;
      if (r['_status'] == 200) {
        setState(() {
          for (final e in (_data!['estudiantes'] as List)) {
            if (ids.contains(e['id'])) e['presente'] = presente;
          }
        });
        if (widget.admin) _load(silencioso: true); // actualiza el historial
      } else {
        _snack((r['error'] ?? 'No se pudo guardar').toString(), error: true);
      }
    } catch (_) {
      if (mounted) _snack('Sin conexión: no se guardó el cambio', error: true);
    } finally {
      if (mounted) setState(() => _ocupados.removeAll(ids));
    }
  }

  Future<void> _guardarLink({required bool cerrar}) async {
    final link = _link.text.trim();
    if (cerrar && link.isEmpty) {
      _snack('Para cerrar la clase debes dejar el link del Meet o de la grabación',
          error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final r = await Api.linkVirtual(widget.horarioId, link, cerrar: cerrar);
      if (!mounted) return;
      if (r['_status'] == 200) {
        _snack(cerrar ? '✓ Clase cerrada' : '✓ Link guardado');
        _load(silencioso: true);
      } else {
        _snack((r['error'] ?? 'No se pudo guardar').toString(), error: true);
      }
    } catch (_) {
      if (mounted) _snack('Sin conexión', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _abrir(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _snack('No se pudo abrir el link', error: true);
    }
  }

  String _fechaLarga(String f) {
    try {
      return DateFormat("EEEE d 'de' MMMM yyyy", 'es_CO').format(DateTime.parse(f));
    } catch (_) {
      return f;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.materia, overflow: TextOverflow.ellipsis),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => Navigator.pop(context)),
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator(color: C.verde))
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: C.tinta.withOpacity(0.6))),
                    const SizedBox(height: 14),
                    ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: () => _load(silencioso: true),
                  color: C.verdeClaro,
                  backgroundColor: C.sup,
                  child: _contenido(),
                ),
    );
  }

  Widget _aviso(String texto, Color color, IconData icono) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(children: [
          Icon(icono, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(color: color, fontSize: 11))),
        ]),
      );

  Widget _contenido() {
    final ests = _ests;
    final presentes = ests.where((e) => e['presente'] == true).length;
    final cerrada = _clase['cerrada'] == true;
    final linkGuardado = (_clase['link'] ?? '').toString();
    final historial = ((_data?['historial'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
            child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(_fechaLarga((_data?['fecha'] ?? '').toString()),
                      style: const TextStyle(
                          color: C.tinta, fontSize: 14, fontWeight: FontWeight.w700))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: C.azul.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('Virtual',
                    style: TextStyle(
                        color: C.azul, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Presentes $presentes de ${ests.length}',
                style: TextStyle(color: C.tinta.withOpacity(0.6), fontSize: 12)),
            if (!widget.admin && !_firmo)
              _aviso(
                  'Primero registra tu asistencia con verificación facial para pasar lista.',
                  C.naranja,
                  Icons.info_outline_rounded),
            if (!widget.admin && _firmo && !_editableTiempo)
              _aviso(
                  'Pasaron más de 24 horas: la lista está bloqueada. Solo el administrador puede cambiarla.',
                  C.rojo,
                  Icons.lock_outline_rounded),
            if (widget.admin && !_editableTiempo)
              _aviso(
                  'Pasaron más de 24 horas: el profesor ya no puede editar. Tú sí puedes.',
                  C.doradoClaro,
                  Icons.lock_open_rounded),
          ]),
        )),
        const SizedBox(height: 12),

        // Link del Meet / grabación
        Card(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Link del Meet o de la grabación',
                style: TextStyle(
                    color: C.tinta, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (widget.admin)
              Row(children: [
                Expanded(
                    child: Text(linkGuardado.isEmpty ? 'Sin link' : linkGuardado,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: C.tinta.withOpacity(0.6), fontSize: 12))),
                if (linkGuardado.isNotEmpty)
                  IconButton(
                      tooltip: 'Abrir link',
                      onPressed: () => _abrir(linkGuardado),
                      icon: const Icon(Icons.open_in_new_rounded, color: C.azul)),
              ])
            else ...[
              TextField(
                controller: _link,
                enabled: _puedeEditar && !_guardando,
                keyboardType: TextInputType.url,
                style: const TextStyle(color: C.tinta, fontSize: 13),
                decoration: const InputDecoration(
                    hintText: 'https://meet.google.com/...',
                    isDense: true),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                  onPressed: (_puedeEditar && !_guardando)
                      ? () => _guardarLink(cerrar: false)
                      : null,
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Guardar link'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: C.tinta,
                      side: const BorderSide(color: C.borde),
                      minimumSize: const Size(0, 42),
                      textStyle: const TextStyle(fontSize: 12)),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton.icon(
                  onPressed: (_puedeEditar && !_guardando)
                      ? () => _guardarLink(cerrar: true)
                      : null,
                  icon: Icon(
                      cerrada ? Icons.check_circle_rounded : Icons.flag_rounded,
                      size: 16),
                  label: Text(cerrada ? 'Clase cerrada' : 'Cerrar clase'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: C.verde,
                      disabledBackgroundColor: C.borde,
                      minimumSize: const Size(0, 42),
                      textStyle: const TextStyle(fontSize: 12)),
                )),
              ]),
              const SizedBox(height: 6),
              Text(
                  'Para cerrar la clase es obligatorio dejar el link. Al cerrarla, los estudiantes ven su resultado de inmediato.',
                  style: TextStyle(color: C.tinta.withOpacity(0.45), fontSize: 11)),
            ],
          ]),
        )),
        const SizedBox(height: 16),

        // Lista de estudiantes
        Row(children: [
          const Expanded(
              child: Text('Lista de estudiantes',
                  style: TextStyle(
                      color: C.tinta, fontSize: 16, fontWeight: FontWeight.w700))),
          if (_puedeEditar && ests.isNotEmpty)
            TextButton(
                onPressed: () => _marcar(
                    ests.where((e) => e['presente'] != true).map((e) => e['id'] as int).toList(),
                    true),
                child: const Text('Todos presentes',
                    style: TextStyle(color: C.verdeClaro, fontSize: 12))),
        ]),
        const SizedBox(height: 8),
        if (ests.isEmpty)
          Card(
              child: Padding(
            padding: const EdgeInsets.all(30),
            child: Center(
                child: Text('No hay estudiantes inscritos',
                    style: TextStyle(color: C.tinta.withOpacity(0.5)))),
          ))
        else
          ...ests.map((e) {
            final id = e['id'] as int;
            final presente = e['presente'] == true;
            final ocupado = _ocupados.contains(id);
            final col = presente ? C.verdeClaro : C.rojo;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                  child: ListTile(
                title: Text((e['nombre'] ?? '').toString(),
                    style: const TextStyle(
                        color: C.tinta, fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(presente ? 'Presente' : 'Ausente',
                    style: TextStyle(
                        color: col, fontSize: 11, fontWeight: FontWeight.w700)),
                trailing: ocupado
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: C.verde))
                    : Switch(
                        value: presente,
                        activeColor: C.verdeClaro,
                        onChanged: _puedeEditar ? (v) => _marcar([id], v) : null),
              )),
            );
          }),

        // Historial de cambios (solo admin)
        if (widget.admin) ...[
          const SizedBox(height: 16),
          const Text('Historial de cambios',
              style: TextStyle(
                  color: C.tinta, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (historial.isEmpty)
            Card(
                child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                  child: Text('Sin cambios registrados',
                      style: TextStyle(color: C.tinta.withOpacity(0.5)))),
            ))
          else
            ...historial.map((h) {
              final accion = (h['accion'] ?? '').toString();
              final ok = accion == 'presente';
              final cuando = (h['hecho_en'] ?? '').toString();
              final hora = cuando.length >= 16
                  ? cuando.substring(0, 16).replaceFirst('T', ' ')
                  : cuando;
              final quien = (h['por_nombre'] ?? '').toString();
              final rol = (h['por_rol'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Card(
                    child: ListTile(
                  dense: true,
                  leading: Icon(
                      ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: ok ? C.verdeClaro : C.rojo,
                      size: 20),
                  title: Text(
                      '${h['estudiante'] ?? ''} → ${ok ? 'Presente' : 'Ausente'}',
                      style: const TextStyle(color: C.tinta, fontSize: 12)),
                  subtitle: Text('$quien ($rol) • $hora',
                      style: TextStyle(
                          color: C.tinta.withOpacity(0.45), fontSize: 11)),
                )),
              );
            }),
        ],
      ],
    );
  }
}
