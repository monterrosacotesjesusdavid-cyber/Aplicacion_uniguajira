import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api.dart';
import '../../core/offline.dart';
import '../../core/ui_kit.dart';

/// Pasar lista a mano cuando NO hay internet.
/// Usa la lista de inscritos descargada antes (mientras había conexión), el profesor
/// marca quién está presente y la lista queda guardada en el celular. Al volver el
/// internet se envía confirmando la identidad del profesor con reconocimiento facial.
class ListaManualOfflineScreen extends StatefulWidget {
  final int horarioId;
  final String materia;
  const ListaManualOfflineScreen({
    super.key,
    required this.horarioId,
    required this.materia,
  });
  @override
  State<ListaManualOfflineScreen> createState() => _ListaManualState();
}

class _ListaManualState extends State<ListaManualOfflineScreen> {
  List _est = [];
  final Set<int> _presentes = {};
  bool _loading = true;
  bool _guardando = false;
  bool _sinLista = false;
  String _buscar = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Api.rosterClase(widget.horarioId);
    final previa = await ListaManualQueue.deHoy(widget.horarioId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (l == null) {
        _sinLista = true;
        return;
      }
      _est = l;
      if (previa != null) {
        _presentes
          ..clear()
          ..addAll((previa['presentes'] as List).map((e) => (e as num).toInt()));
      }
    });
  }

  List get _visibles {
    final q = _buscar.trim().toLowerCase();
    if (q.isEmpty) return _est;
    return _est.where((e) =>
        (e['nombre'] ?? '').toString().toLowerCase().contains(q) ||
        (e['usuario'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  void _marcarTodos(bool v) => setState(() {
        for (final e in _visibles) {
          final id = (e['id'] as num).toInt();
          v ? _presentes.add(id) : _presentes.remove(id);
        }
      });

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    await ListaManualQueue.guardar(
      horarioId: widget.horarioId,
      materia: widget.materia,
      presentes: _presentes.toList(),
      total: _est.length,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Lista guardada (${_presentes.length} de ${_est.length} presentes). '
          'Se enviará cuando haya internet.'),
      backgroundColor: C.verde,
    ));
    Navigator.pop(context, true);
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.verde))
          : _sinLista
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No hay una lista de estudiantes guardada para esta clase.\n\n'
                      'Abre la app con internet al menos una vez antes de la clase '
                      'para descargarla.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: C.suave, height: 1.4)),
                  ),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: AvisoEstado(
                      icono: Icons.cloud_off_rounded,
                      color: Colors.orange,
                      texto: 'Sin conexión: marca a los presentes. La lista se enviará '
                          'cuando vuelva el internet.'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      onChanged: (v) => setState(() => _buscar = v),
                      style: TextStyle(color: C.tinta),
                      decoration: const InputDecoration(
                        hintText: 'Buscar estudiante',
                        prefixIcon: Icon(Icons.search_rounded)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(children: [
                      Expanded(
                        child: Text('Presentes: ${_presentes.length} de ${_est.length}',
                            style: TextStyle(
                                color: C.tinta70, fontWeight: FontWeight.w600)),
                      ),
                      TextButton(
                          onPressed: () => _marcarTodos(true),
                          child: Text('Todos',
                              style: TextStyle(color: C.verdeClaro))),
                      TextButton(
                          onPressed: () => _marcarTodos(false),
                          child: Text('Ninguno',
                              style: TextStyle(color: C.suave))),
                    ]),
                  ),
                  Expanded(
                    child: _est.isEmpty
                        ? Center(
                            child: Text('Esta clase no tiene estudiantes inscritos',
                                style: TextStyle(color: C.suave)))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: _visibles.length,
                            itemBuilder: (_, i) {
                              final e = _visibles[i];
                              final id = (e['id'] as num).toInt();
                              final on = _presentes.contains(id);
                              return CheckboxListTile(
                                value: on,
                                activeColor: C.verde,
                                onChanged: (v) => setState(() =>
                                    v == true ? _presentes.add(id) : _presentes.remove(id)),
                                title: Text((e['nombre'] ?? '').toString(),
                                    style: TextStyle(color: C.tinta)),
                                subtitle: Text((e['usuario'] ?? '').toString(),
                                    style: TextStyle(color: C.suave, fontSize: 12)),
                              );
                            },
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: ElevatedButton.icon(
                        onPressed: (_guardando || _est.isEmpty) ? null : _guardar,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: Text(_guardando ? 'Guardando...' : 'Guardar lista'),
                        style: estiloBoton(fondo: C.verde),
                      ),
                    ),
                  ),
                ]),
    );
  }
}
