import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../../app/core/errors/app_exceptions.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import 'report_export_mapper.dart';
import 'report_filter_preset_support.dart';

class ReportExportPdfSupport {
  static Future<_PdfFontBundle>? _fontBundleFuture;

  Future<File> saveToTemporary(ReportExportDocument document) async {
    try {
      final directory = await _ensureExportDirectory();
      final file = File(
        p.join(
          directory.path,
          '${_buildFileName(document, generatedAt: document.generatedAt)}.pdf',
        ),
      );
      await file.writeAsBytes(await buildPdfBytes(document), flush: true);
      return file;
    } catch (error) {
      throw ValidationException(
        'Nao foi possivel gerar o PDF do relatorio.',
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
        'Nao foi possivel compartilhar o PDF do relatorio.',
        cause: error,
      );
    }
  }

  Future<List<int>> buildPdfBytes(ReportExportDocument document) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(
          base: fonts.base,
          bold: fonts.bold,
        ),
        build: (_) => [
          _buildHeader(document),
          pw.SizedBox(height: 16),
          _buildMetadata(document),
          if (document.metrics.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _buildMetrics(document),
          ],
          for (final table in document.tables) ...[
            pw.SizedBox(height: 16),
            _buildTable(table),
          ],
          pw.SizedBox(height: 22),
          pw.Text(
            'Tatuzin - relatorio gerado localmente em ${AppFormatters.shortDateTime(document.generatedAt)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  pw.Widget _buildHeader(ReportExportDocument document) {
    const brand = PdfColor.fromInt(0xFF6B4F3A);
    const surface = PdfColor.fromInt(0xFFF6EEE4);

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: surface,
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFD2C1AA)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  document.businessName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: brand,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  document.title,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  document.periodLabel,
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Modo ${document.mode.label}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: brand,
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Text(
              document.page.label,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMetadata(ReportExportDocument document) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Contexto',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          _metaLine('Gerado em', AppFormatters.shortDateTime(document.generatedAt)),
          _metaLine('Modo', document.mode.label),
          _metaLine('Periodo', document.periodLabel),
          _metaLine(
            'Filtros',
            document.filterSummary.isEmpty
                ? 'Sem filtros adicionais.'
                : document.filterSummary.join(' | '),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMetrics(ReportExportDocument document) {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final metric in document.metrics)
          pw.Container(
            width: 250,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFAF7F2),
              borderRadius: pw.BorderRadius.circular(14),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  metric.label,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  metric.value,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (metric.caption?.isNotEmpty ?? false) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    metric.caption!,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget _buildTable(ReportExportTable table) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            table.title,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          if (table.subtitle?.isNotEmpty ?? false) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              table.subtitle!,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
          pw.SizedBox(height: 10),
          if (table.rows.isEmpty)
            pw.Text(
              table.emptyMessage,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            )
          else
            pw.Table(
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColors.grey300),
              ),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF3ECE2),
                  ),
                  children: [
                    for (final column in table.columns)
                      _tableCell(column, bold: true),
                  ],
                ),
                for (final row in table.rows)
                  pw.TableRow(
                    children: [
                      for (final value in row) _tableCell(value),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }

  pw.Widget _metaLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 74,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _tableCell(String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
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

  Future<_PdfFontBundle> _loadFonts() {
    return _fontBundleFuture ??= _createFontBundle();
  }

  Future<_PdfFontBundle> _createFontBundle() async {
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    return _PdfFontBundle(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
  }
}

class _PdfFontBundle {
  const _PdfFontBundle({
    required this.base,
    required this.bold,
  });

  final pw.Font base;
  final pw.Font bold;
}
