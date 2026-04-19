import 'package:flutter/material.dart';

import '../../data/support/report_export_mapper.dart';
import 'report_export_menu.dart';

class ReportExportButton extends StatefulWidget {
  const ReportExportButton({
    super.key,
    required this.onExportPdf,
    required this.onExportCsv,
  });

  final Future<void> Function(ReportExportMode mode) onExportPdf;
  final Future<void> Function(ReportExportMode mode) onExportCsv;

  @override
  State<ReportExportButton> createState() => _ReportExportButtonState();
}

class _ReportExportButtonState extends State<ReportExportButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ReportExportMenu(
      enabled: !_busy,
      onSelected: _handleSelection,
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined),
          label: Text(_busy ? 'Exportando...' : 'Exportar'),
        ),
      ),
    );
  }

  Future<void> _handleSelection(ReportExportSelection selection) async {
    setState(() => _busy = true);
    try {
      switch (selection.format) {
        case ReportExportFormat.pdf:
          await widget.onExportPdf(selection.mode);
        case ReportExportFormat.csv:
          await widget.onExportCsv(selection.mode);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nao foi possivel exportar o relatorio: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
