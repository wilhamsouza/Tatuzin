import 'package:flutter/material.dart';

import '../../data/support/report_export_mapper.dart';

enum ReportExportFormat { pdf, csv }

class ReportExportSelection {
  const ReportExportSelection({required this.format, required this.mode});

  final ReportExportFormat format;
  final ReportExportMode mode;
}

class ReportExportMenu extends StatelessWidget {
  const ReportExportMenu({
    super.key,
    required this.child,
    required this.onSelected,
    this.enabled = true,
  });

  final Widget child;
  final ValueChanged<ReportExportSelection> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ReportExportSelection>(
      enabled: enabled,
      tooltip: 'Exportar relatorio',
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: ReportExportSelection(
            format: ReportExportFormat.pdf,
            mode: ReportExportMode.summary,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('PDF resumo'),
          ),
        ),
        PopupMenuItem(
          value: ReportExportSelection(
            format: ReportExportFormat.pdf,
            mode: ReportExportMode.detailed,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.picture_as_pdf_rounded),
            title: Text('PDF detalhado'),
          ),
        ),
        PopupMenuItem(
          value: ReportExportSelection(
            format: ReportExportFormat.csv,
            mode: ReportExportMode.summary,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.table_view_outlined),
            title: Text('CSV resumo'),
          ),
        ),
        PopupMenuItem(
          value: ReportExportSelection(
            format: ReportExportFormat.csv,
            mode: ReportExportMode.detailed,
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.view_list_outlined),
            title: Text('CSV detalhado'),
          ),
        ),
      ],
      child: child,
    );
  }
}
