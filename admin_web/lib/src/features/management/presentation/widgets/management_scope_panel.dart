import 'package:flutter/material.dart';

import '../../../../core/models/admin_models.dart';
import '../../../../core/widgets/admin_surface.dart';

class ManagementScopeSelection {
  const ManagementScopeSelection({
    required this.companyId,
    required this.startDate,
    required this.endDate,
    required this.topN,
    this.force = false,
  });

  final String companyId;
  final String startDate;
  final String endDate;
  final int topN;
  final bool force;
}

class ManagementScopePanel extends StatefulWidget {
  const ManagementScopePanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.companies,
    required this.selection,
    required this.onApply,
  });

  final String title;
  final String subtitle;
  final List<AdminCompanySummary> companies;
  final ManagementScopeSelection selection;
  final ValueChanged<ManagementScopeSelection> onApply;

  @override
  State<ManagementScopePanel> createState() => _ManagementScopePanelState();
}

class _ManagementScopePanelState extends State<ManagementScopePanel> {
  late final TextEditingController _startDateController;
  late final TextEditingController _endDateController;
  late final TextEditingController _topNController;
  late String _selectedCompanyId;

  @override
  void initState() {
    super.initState();
    _selectedCompanyId = widget.selection.companyId;
    _startDateController = TextEditingController(
      text: widget.selection.startDate,
    );
    _endDateController = TextEditingController(text: widget.selection.endDate);
    _topNController = TextEditingController(text: '${widget.selection.topN}');
  }

  @override
  void didUpdateWidget(covariant ManagementScopePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      _selectedCompanyId = widget.selection.companyId;
      _startDateController.text = widget.selection.startDate;
      _endDateController.text = widget.selection.endDate;
      _topNController.text = '${widget.selection.topN}';
    }
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _topNController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: widget.title,
      subtitle: widget.subtitle,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCompanyId,
              decoration: const InputDecoration(labelText: 'Empresa'),
              items: widget.companies
                  .map(
                    (company) => DropdownMenuItem<String>(
                      value: company.id,
                      child: Text(company.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedCompanyId = value);
                }
              },
            ),
          ),
          SizedBox(
            width: 160,
            child: TextField(
              controller: _startDateController,
              decoration: const InputDecoration(
                labelText: 'Inicio',
                hintText: 'YYYY-MM-DD',
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: TextField(
              controller: _endDateController,
              decoration: const InputDecoration(
                labelText: 'Fim',
                hintText: 'YYYY-MM-DD',
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _topNController,
              decoration: const InputDecoration(labelText: 'Top N'),
              keyboardType: TextInputType.number,
            ),
          ),
          FilledButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.insights_rounded),
            label: const Text('Aplicar'),
          ),
          TextButton(
            onPressed: _applyForce,
            child: const Text('Rematerializar'),
          ),
        ],
      ),
    );
  }

  void _apply() {
    widget.onApply(
      ManagementScopeSelection(
        companyId: _selectedCompanyId,
        startDate: _startDateController.text.trim(),
        endDate: _endDateController.text.trim(),
        topN:
            int.tryParse(_topNController.text.trim()) ?? widget.selection.topN,
      ),
    );
  }

  void _applyForce() {
    widget.onApply(
      ManagementScopeSelection(
        companyId: _selectedCompanyId,
        startDate: _startDateController.text.trim(),
        endDate: _endDateController.text.trim(),
        topN:
            int.tryParse(_topNController.text.trim()) ?? widget.selection.topN,
        force: true,
      ),
    );
  }
}
