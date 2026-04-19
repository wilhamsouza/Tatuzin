import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import 'report_export_mapper.dart';

class ReportExportCsvSupport {
  Future<File> saveToTemporary(ReportExportDocument document) async {
    try {
      final directory = await _ensureExportDirectory();
      final file = File(
        p.join(
          directory.path,
          '${_buildFileName(document, generatedAt: document.generatedAt)}.csv',
        ),
      );
      await file.writeAsString(buildCsv(document), flush: true);
      return file;
    } catch (error) {
      throw ValidationException(
        'Nao foi possivel gerar o CSV do relatorio.',
        cause: error,
      );
    }
  }

  Future<void> share(ReportExportDocument document) async {
    try {
      final file = await saveToTemporary(document);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: document.title,
        text:
            '${document.title} (${document.mode.label}) - ${document.businessName}',
      );
    } catch (error) {
      throw ValidationException(
        'Nao foi possivel compartilhar o CSV do relatorio.',
        cause: error,
      );
    }
  }

  String buildCsv(ReportExportDocument document) {
    final buffer = StringBuffer();
    void writeRow(List<String> values) {
      buffer.writeln(values.map(_escape).join(';'));
    }

    writeRow(['Relatorio', document.title]);
    writeRow(['Empresa', document.businessName]);
    writeRow(['Modo', document.mode.label]);
    writeRow(['Periodo', document.periodLabel]);
    writeRow(['Gerado em', AppFormatters.shortDateTime(document.generatedAt)]);
    if ((document.navigationSummary ?? '').trim().isNotEmpty) {
      writeRow(['Drill-down', document.navigationSummary!.trim()]);
    }
    writeRow(['Filtros', document.filterSummary.join(' | ')]);
    buffer.writeln();
    writeRow(document.csvHeaders);
    for (final row in document.csvRows) {
      writeRow(row);
    }
    return buffer.toString();
  }

  String _escape(String value) {
    final normalized = value.replaceAll('"', '""');
    return '"$normalized"';
  }

  Future<Directory> _ensureExportDirectory() async {
    final tempDirectory = await getTemporaryDirectory();
    final directory = Directory(p.join(tempDirectory.path, 'relatorios'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _buildFileName(
    ReportExportDocument document, {
    required DateTime generatedAt,
  }) {
    final stamp = [
      generatedAt.year.toString().padLeft(4, '0'),
      generatedAt.month.toString().padLeft(2, '0'),
      generatedAt.day.toString().padLeft(2, '0'),
      '_',
      generatedAt.hour.toString().padLeft(2, '0'),
      generatedAt.minute.toString().padLeft(2, '0'),
    ].join();
    return '${document.fileStem}_${document.mode.fileSuffix}_$stamp';
  }
}
