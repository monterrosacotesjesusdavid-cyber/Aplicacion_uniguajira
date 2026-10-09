import 'dart:math' as math;
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Genera la planilla de asistencia de una MATERIA en PDF (horizontal, tipo matriz):
/// una fila por estudiante, una columna por fecha de clase y el porcentaje al final.
/// Incluye todas las fechas del semestre y todos los días de la materia. Si hay muchas
/// fechas, se reparten en varias tablas (los totales P, T, A y % van en la última).
class PlanillaPdf {
  static String _ddmm(String f) =>
      f.length >= 10 ? '${f.substring(8, 10)}/${f.substring(5, 7)}' : f;

  static String _hhmm(dynamic h) {
    final s = (h ?? '').toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  static Future<Uint8List> generar(Map data) async {
    final clase = Map<String, dynamic>.from(data['clase'] as Map);
    final ests = (data['estudiantes'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Fechas de clase (columnas), de la más antigua a la más reciente
    final set = <String>{};
    for (final e in ests) {
      for (final r in (e['registros'] as List)) {
        set.add((r as Map)['fecha'] as String);
      }
    }
    final fechas = set.toList()..sort();

    // Resumen general
    int bajo = 0, sumaPct = 0;
    for (final e in ests) {
      final p = (e['porcentaje'] as num).toInt();
      sumaPct += p;
      if ((e['total'] as num) > 0 && p < 75) bajo++;
    }
    final promedio = ests.isEmpty ? 0 : (sumaPct / ests.length).round();

    // Las fechas se reparten en tablas de máximo 20 columnas para que quepan en la hoja.
    const porTabla = 20;
    final chunks = <List<String>>[];
    for (var i = 0; i < fechas.length; i += porTabla) {
      chunks.add(fechas.sublist(i, math.min(i + porTabla, fechas.length)));
    }
    if (chunks.isEmpty) chunks.add(<String>[]);

    // Estado de cada estudiante por fecha
    final porFechaEst = <int, Map<String, String>>{};
    for (var i = 0; i < ests.length; i++) {
      final m = <String, String>{};
      for (final r in (ests[i]['registros'] as List)) {
        final mm = r as Map;
        final est = mm['estado'];
        m[mm['fecha'] as String] =
            est == 'presente' ? 'P' : est == 'tardanza' ? 'T' : 'A';
      }
      porFechaEst[i] = m;
    }

    final oscuro = PdfColor.fromHex('#06222A');
    final verde = PdfColor.fromHex('#00899D');
    final generado = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final horario = (clase['horario_texto'] ??
            '${clase['dia'] ?? ''} ${_hhmm(clase['hora_inicio'])} - ${_hhmm(clase['hora_fin'])}')
        .toString();

    // Construye una tabla por cada bloque de fechas.
    List<pw.Widget> tablas() {
      final out = <pw.Widget>[];
      for (var k = 0; k < chunks.length; k++) {
        final cf = chunks[k];
        final ultimo = k == chunks.length - 1;
        final headers = <String>[
          'N', 'Estudiante', ...cf.map(_ddmm),
          if (ultimo) ...['P', 'T', 'A', '%'],
        ];
        final filas = <List<String>>[];
        for (var i = 0; i < ests.length; i++) {
          final e = ests[i];
          filas.add([
            '${i + 1}',
            (e['nombre'] ?? '').toString(),
            ...cf.map((f) => porFechaEst[i]![f] ?? '-'),
            if (ultimo) ...[
              '${e['presentes']}', '${e['tardanzas']}', '${e['ausentes']}',
              '${e['porcentaje']}%',
            ],
          ]);
        }
        final base = 2 + cf.length;
        final colWidths = <int, pw.TableColumnWidth>{
          0: const pw.FixedColumnWidth(22),
          1: const pw.FlexColumnWidth(),
        };
        for (var i = 0; i < cf.length; i++) {
          colWidths[2 + i] = const pw.FixedColumnWidth(27);
        }
        if (ultimo) {
          colWidths[base] = const pw.FixedColumnWidth(20);
          colWidths[base + 1] = const pw.FixedColumnWidth(20);
          colWidths[base + 2] = const pw.FixedColumnWidth(20);
          colWidths[base + 3] = const pw.FixedColumnWidth(34);
        }
        final alineacion = <int, pw.Alignment>{
          for (var i = 0; i < headers.length; i++) i: pw.Alignment.center,
          1: pw.Alignment.centerLeft,
        };
        if (chunks.length > 1 && cf.isNotEmpty) {
          out.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
                'Clases del ${_ddmm(cf.first)} al ${_ddmm(cf.last)}  (tabla ${k + 1} de ${chunks.length})',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: oscuro))));
        }
        out.add(pw.TableHelper.fromTextArray(
          headers: headers,
          data: filas,
          columnWidths: colWidths,
          cellAlignments: alineacion,
          headerAlignments: alineacion,
          headerStyle: pw.TextStyle(
              fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: verde),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
          cellDecoration: (col, data, row) {
            final v = data.toString();
            if (col >= 2 && col < base) {
              if (v == 'A') return const pw.BoxDecoration(color: PdfColors.red100);
              if (v == 'T') return const pw.BoxDecoration(color: PdfColors.orange100);
            }
            if (ultimo && col == base + 3) {
              final n = int.tryParse(v.replaceAll('%', '')) ?? 0;
              if (n < 75) return const pw.BoxDecoration(color: PdfColors.red100);
            }
            return const pw.BoxDecoration();
          },
        ));
        if (!ultimo) out.add(pw.SizedBox(height: 14));
      }
      return out;
    }

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: verde, width: 1.5))),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('UNIVERSIDAD DE LA GUAJIRA',
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold, color: oscuro)),
              pw.Text('Planilla de asistencia',
                  style: pw.TextStyle(fontSize: 11, color: verde)),
            ]),
      ),
      footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generado: $generado',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.Text('Pagina ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ]),
      build: (ctx) => [
        pw.Text((clase['materia'] ?? '').toString(),
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Profesor: ${clase['profesor'] ?? ''}    |    Salon: ${clase['salon'] ?? ''}    |    Horario: $horario',
            style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Estudiantes: ${ests.length}    |    Promedio de asistencia: $promedio%    |    Por debajo del 75%: $bajo',
            style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        if (ests.isEmpty)
          pw.Text('No hay estudiantes inscritos en esta materia.')
        else
          ...tablas(),
        pw.SizedBox(height: 10),
        pw.Text(
            'P = Presente   T = Tardanza   A = Ausente   - = sin clase para el estudiante   '
            '% = (P + T) / total de clases.  Minimo requerido: 75%.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    return doc.save();
  }

  /// Genera el PDF y abre el menú del sistema para guardarlo o compartirlo.
  static Future<void> compartir(Map data) async {
    final bytes = await generar(data);
    final clase = Map<String, dynamic>.from(data['clase'] as Map);
    final nombre = (clase['materia'] ?? 'clase')
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final fecha = DateFormat('yyyyMMdd').format(DateTime.now());
    await Printing.sharePdf(bytes: bytes, filename: 'planilla_${nombre}_$fecha.pdf');
  }
}
