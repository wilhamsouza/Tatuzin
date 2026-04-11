import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../app/core/errors/app_exceptions.dart';
import '../../../app/core/formatters/app_formatters.dart';
import '../domain/entities/commercial_receipt.dart';
import '../domain/entities/commercial_receipt_detail_line.dart';
import '../domain/entities/commercial_receipt_item.dart';

class ReceiptPdfService {
  Future<File> saveToDocuments(CommercialReceipt receipt) {
    return _buildFile(receipt, persistent: true);
  }

  Future<File> saveToTemporary(CommercialReceipt receipt) {
    return _buildFile(receipt, persistent: false);
  }

  Future<File> _buildFile(
    CommercialReceipt receipt, {
    required bool persistent,
  }) async {
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            _buildHeader(receipt),
            pw.SizedBox(height: 18),
            _buildDetailsSection('Operacao', receipt.operationDetails),
            if (receipt.hasItems) ...[
              pw.SizedBox(height: 16),
              _buildItemsSection(receipt),
            ],
            pw.SizedBox(height: 16),
            _buildSummarySection(receipt),
            if (receipt.extraDetails.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              _buildDetailsSection(
                'Informacoes adicionais',
                receipt.extraDetails,
              ),
            ],
            if (receipt.notes?.isNotEmpty ?? false) ...[
              pw.SizedBox(height: 16),
              _buildNotesSection(receipt.notes!),
            ],
            pw.SizedBox(height: 22),
            pw.Text(
              receipt.footerMessage,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      );

      final directory = persistent
          ? await _receiptDocumentsDirectory()
          : await getTemporaryDirectory();
      final file = File(
        p.join(directory.path, '${_buildFileName(receipt)}.pdf'),
      );

      await file.writeAsBytes(await pdf.save(), flush: true);
      return file;
    } catch (error) {
      throw ValidationException(
        'Nao foi possivel gerar o PDF do comprovante.',
        cause: error,
      );
    }
  }

  Future<Directory> _receiptDocumentsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final receiptsDir = Directory(p.join(root.path, 'comprovantes'));
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }
    return receiptsDir;
  }

  String _buildFileName(CommercialReceipt receipt) {
    final stamp = [
      receipt.issuedAt.year.toString().padLeft(4, '0'),
      receipt.issuedAt.month.toString().padLeft(2, '0'),
      receipt.issuedAt.day.toString().padLeft(2, '0'),
      '_',
      receipt.issuedAt.hour.toString().padLeft(2, '0'),
      receipt.issuedAt.minute.toString().padLeft(2, '0'),
    ].join();

    final normalizedIdentifier = receipt.identifier
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    return '${receipt.type.filePrefix}_${normalizedIdentifier}_$stamp';
  }

  pw.Widget _buildHeader(CommercialReceipt receipt) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(18),
        color: const PdfColor.fromInt(0xFF6C4CF1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            receipt.businessName,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            receipt.title,
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.white),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Documento ${receipt.identifier}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
          ),
          pw.Text(
            AppFormatters.shortDateTime(receipt.issuedAt),
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(999),
            ),
            child: pw.Text(
              receipt.statusLabel,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF6C4CF1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDetailsSection(
    String title,
    List<CommercialReceiptDetailLine> details,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          for (final detail in details) ...[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    detail.label,
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(
                    detail.value,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildItemsSection(CommercialReceipt receipt) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Itens',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(5),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell('Descricao', bold: true),
                  _tableCell('Qtd', bold: true, alignRight: true),
                  _tableCell('Unit.', bold: true, alignRight: true),
                  _tableCell('Subtotal', bold: true, alignRight: true),
                ],
              ),
              for (final item in receipt.items)
                pw.TableRow(
                  children: [
                    _itemDescriptionCell(item),
                    _tableCell(item.quantityLabel, alignRight: true),
                    _tableCell(
                      AppFormatters.currencyFromCents(item.unitPriceCents),
                      alignRight: true,
                    ),
                    _tableCell(
                      AppFormatters.currencyFromCents(item.subtotalCents),
                      alignRight: true,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummarySection(CommercialReceipt receipt) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(16),
        color: PdfColors.grey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Resumo financeiro',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          _summaryRow(
            receipt.subtotalLabel,
            AppFormatters.currencyFromCents(receipt.subtotalCents),
          ),
          if (receipt.discountCents > 0)
            _summaryRow(
              'Desconto',
              AppFormatters.currencyFromCents(receipt.discountCents),
            ),
          if (receipt.surchargeCents > 0)
            _summaryRow(
              'Acrescimo',
              AppFormatters.currencyFromCents(receipt.surchargeCents),
            ),
          if (receipt.paymentMethodLabel != null)
            _summaryRow('Forma', receipt.paymentMethodLabel!),
          pw.Divider(color: PdfColors.grey400, height: 16),
          _summaryRow(
            receipt.totalLabel,
            AppFormatters.currencyFromCents(receipt.totalCents),
            emphasize: true,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildNotesSection(String notes) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Observacoes',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Text(notes, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  pw.Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    final style = pw.TextStyle(
      fontSize: emphasize ? 14 : 10,
      fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  pw.Widget _tableCell(
    String value, {
    bool bold = false,
    bool alignRight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        value,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _itemDescriptionCell(CommercialReceiptItem item) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            item.title,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          if (item.supportingLines.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            for (final line in item.supportingLines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                child: pw.Text(
                  line,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
