import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/admin_providers.dart';
import '../../../../core/models/admin_crm_models.dart';
import '../../../../core/models/admin_models.dart';
import '../../../../core/utils/admin_formatters.dart';
import '../../../../core/widgets/admin_surface.dart';

class CrmCustomerDetailPage extends ConsumerStatefulWidget {
  const CrmCustomerDetailPage({
    super.key,
    required this.customerId,
    this.initialCompanyId,
  });

  final String customerId;
  final String? initialCompanyId;

  @override
  ConsumerState<CrmCustomerDetailPage> createState() =>
      _CrmCustomerDetailPageState();
}

class _CrmCustomerDetailPageState extends ConsumerState<CrmCustomerDetailPage> {
  late final TextEditingController _tagsController;
  late final TextEditingController _noteController;
  late final TextEditingController _taskTitleController;
  late final TextEditingController _taskDescriptionController;
  late final TextEditingController _taskDueDateController;
  String? _selectedCompanyId;
  bool _isSavingTags = false;
  bool _isSavingNote = false;
  bool _isSavingTask = false;

  @override
  void initState() {
    super.initState();
    _selectedCompanyId = widget.initialCompanyId;
    _tagsController = TextEditingController();
    _noteController = TextEditingController();
    _taskTitleController = TextEditingController();
    _taskDescriptionController = TextEditingController();
    _taskDueDateController = TextEditingController();
  }

  @override
  void dispose() {
    _tagsController.dispose();
    _noteController.dispose();
    _taskTitleController.dispose();
    _taskDescriptionController.dispose();
    _taskDueDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.customerId.trim().isEmpty) {
      return const AdminSurface(
        title: 'Cliente CRM invalido',
        subtitle: 'Abra o detalhe a partir da lista de clientes do CRM.',
        child: SizedBox.shrink(),
      );
    }

    final companiesAsync = ref.watch(adminManagementCompanyOptionsProvider);

    return companiesAsync.when(
      data: (companies) {
        if (companies.isEmpty) {
          return const AdminSurface(
            title: 'Sem empresas para CRM',
            subtitle:
                'Nao ha empresas disponiveis para abrir o detalhe do cliente CRM.',
            child: SizedBox.shrink(),
          );
        }

        final effectiveCompanyId = _resolveCompanyId(companies);
        final key = AdminCrmCustomerKey(
          companyId: effectiveCompanyId,
          customerId: widget.customerId,
        );
        final timelineQuery = AdminCrmCustomerTimelineQuery(
          companyId: effectiveCompanyId,
          customerId: widget.customerId,
          page: 1,
          pageSize: 40,
        );
        final detailAsync = ref.watch(adminCrmCustomerDetailProvider(key));
        final timelineAsync = ref.watch(
          adminCrmCustomerTimelineProvider(timelineQuery),
        );

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CrmDetailScopePanel(
                companies: companies,
                selectedCompanyId: effectiveCompanyId,
                onCompanyChanged: (value) {
                  setState(() => _selectedCompanyId = value);
                },
                onBack: () => context.go(
                  '/management/crm/customers?companyId=$effectiveCompanyId',
                ),
              ),
              const SizedBox(height: 24),
              if (detailAsync.hasError)
                AdminSurface(
                  title: 'Nao foi possivel carregar o cliente CRM',
                  subtitle: detailAsync.error.toString(),
                  child: FilledButton.tonal(
                    onPressed: _refreshCrm,
                    child: const Text('Tentar novamente'),
                  ),
                )
              else if (timelineAsync.hasError)
                AdminSurface(
                  title: 'Nao foi possivel carregar a timeline CRM',
                  subtitle: timelineAsync.error.toString(),
                  child: FilledButton.tonal(
                    onPressed: _refreshCrm,
                    child: const Text('Tentar novamente'),
                  ),
                )
              else if (detailAsync.isLoading ||
                  timelineAsync.isLoading ||
                  detailAsync.asData?.value == null ||
                  timelineAsync.asData?.value == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                _CrmCustomerContent(
                  detail: detailAsync.asData!.value,
                  timeline: timelineAsync.asData!.value,
                  tagsController: _tagsController,
                  noteController: _noteController,
                  taskTitleController: _taskTitleController,
                  taskDescriptionController: _taskDescriptionController,
                  taskDueDateController: _taskDueDateController,
                  isSavingTags: _isSavingTags,
                  isSavingNote: _isSavingNote,
                  isSavingTask: _isSavingTask,
                  onApplyTags: () => _applyTags(key),
                  onClearTags: () => _applyTags(key, labels: const <String>[]),
                  onCreateNote: () => _createNote(key),
                  onCreateTask: () => _createTask(key),
                ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Nao foi possivel carregar as empresas',
        subtitle: error.toString(),
        child: const SizedBox.shrink(),
      ),
    );
  }

  String _resolveCompanyId(List<AdminCompanySummary> companies) {
    final requestedCompanyId = _selectedCompanyId ?? widget.initialCompanyId;
    for (final company in companies) {
      if (company.id == requestedCompanyId) {
        return company.id;
      }
    }
    return companies.first.id;
  }

  Future<void> _applyTags(
    AdminCrmCustomerKey key, {
    List<String>? labels,
  }) async {
    final effectiveLabels =
        labels ??
        _tagsController.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);

    if (labels == null && effectiveLabels.isEmpty) {
      _showMessage('Informe ao menos uma tag separada por virgula.');
      return;
    }

    setState(() => _isSavingTags = true);
    try {
      await ref
          .read(adminApiServiceProvider)
          .applyCrmCustomerTags(key: key, labels: effectiveLabels);
      _tagsController.clear();
      _refreshCrm();
      _showMessage(
        effectiveLabels.isEmpty
            ? 'Tags CRM removidas com sucesso.'
            : 'Tags CRM atualizadas com sucesso.',
      );
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSavingTags = false);
      }
    }
  }

  Future<void> _createNote(AdminCrmCustomerKey key) async {
    final body = _noteController.text.trim();
    if (body.isEmpty) {
      _showMessage('Escreva a nota CRM antes de salvar.');
      return;
    }

    setState(() => _isSavingNote = true);
    try {
      await ref
          .read(adminApiServiceProvider)
          .createCrmCustomerNote(key: key, body: body);
      _noteController.clear();
      _refreshCrm();
      _showMessage('Nota CRM criada com sucesso.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSavingNote = false);
      }
    }
  }

  Future<void> _createTask(AdminCrmCustomerKey key) async {
    final title = _taskTitleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Informe o titulo da tarefa CRM.');
      return;
    }

    DateTime? dueAt;
    final dueDateText = _taskDueDateController.text.trim();
    if (dueDateText.isNotEmpty) {
      dueAt = DateTime.tryParse(dueDateText);
      if (dueAt == null) {
        _showMessage('Use a data no formato YYYY-MM-DD.', isError: true);
        return;
      }
    }

    setState(() => _isSavingTask = true);
    try {
      await ref
          .read(adminApiServiceProvider)
          .createCrmCustomerTask(
            key: key,
            title: title,
            description: _taskDescriptionController.text.trim().isEmpty
                ? null
                : _taskDescriptionController.text.trim(),
            dueAt: dueAt,
          );
      _taskTitleController.clear();
      _taskDescriptionController.clear();
      _taskDueDateController.clear();
      _refreshCrm();
      _showMessage('Tarefa CRM criada com sucesso.');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSavingTask = false);
      }
    }
  }

  void _refreshCrm() {
    ref.read(adminRefreshTickProvider.notifier).state++;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _CrmCustomerContent extends StatelessWidget {
  const _CrmCustomerContent({
    required this.detail,
    required this.timeline,
    required this.tagsController,
    required this.noteController,
    required this.taskTitleController,
    required this.taskDescriptionController,
    required this.taskDueDateController,
    required this.isSavingTags,
    required this.isSavingNote,
    required this.isSavingTask,
    required this.onApplyTags,
    required this.onClearTags,
    required this.onCreateNote,
    required this.onCreateTask,
  });

  final AdminCrmCustomerDetail detail;
  final AdminPaginatedResult<AdminCrmTimelineEvent> timeline;
  final TextEditingController tagsController;
  final TextEditingController noteController;
  final TextEditingController taskTitleController;
  final TextEditingController taskDescriptionController;
  final TextEditingController taskDueDateController;
  final bool isSavingTags;
  final bool isSavingNote;
  final bool isSavingTask;
  final VoidCallback onApplyTags;
  final VoidCallback onClearTags;
  final VoidCallback onCreateNote;
  final VoidCallback onCreateTask;

  @override
  Widget build(BuildContext context) {
    final customer = detail.customer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CustomerSummarySurface(customer: customer),
        const SizedBox(height: 24),
        _CommercialSummaryGrid(summary: customer.commercialSummary),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final tagsSurface = _TagsSurface(
              customer: customer,
              controller: tagsController,
              isSaving: isSavingTags,
              onApply: onApplyTags,
              onClear: onClearTags,
            );
            final noteComposer = _NoteComposerSurface(
              controller: noteController,
              isSaving: isSavingNote,
              onCreate: onCreateNote,
            );
            final taskComposer = _TaskComposerSurface(
              titleController: taskTitleController,
              descriptionController: taskDescriptionController,
              dueDateController: taskDueDateController,
              isSaving: isSavingTask,
              onCreate: onCreateTask,
            );

            if (constraints.maxWidth < 1200) {
              return Column(
                children: [
                  tagsSurface,
                  const SizedBox(height: 24),
                  noteComposer,
                  const SizedBox(height: 24),
                  taskComposer,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tagsSurface),
                const SizedBox(width: 24),
                Expanded(child: noteComposer),
                const SizedBox(width: 24),
                Expanded(child: taskComposer),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final notesSurface = _NotesSurface(notes: detail.notes);
            final tasksSurface = _TasksSurface(tasks: detail.tasks);

            if (constraints.maxWidth < 1200) {
              return Column(
                children: [
                  notesSurface,
                  const SizedBox(height: 24),
                  tasksSurface,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: notesSurface),
                const SizedBox(width: 24),
                Expanded(child: tasksSurface),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _TimelineSurface(timeline: timeline, customerName: customer.name),
      ],
    );
  }
}

class _CrmDetailScopePanel extends StatelessWidget {
  const _CrmDetailScopePanel({
    required this.companies,
    required this.selectedCompanyId,
    required this.onCompanyChanged,
    required this.onBack,
  });

  final List<AdminCompanySummary> companies;
  final String selectedCompanyId;
  final ValueChanged<String> onCompanyChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Escopo do cliente CRM',
      subtitle:
          'O detalhe do cliente sempre e lido por empresa no backend, separado da consulta operacional do app.',
      trailing: OutlinedButton.icon(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Voltar para lista'),
      ),
      child: SizedBox(
        width: 320,
        child: DropdownButtonFormField<String>(
          initialValue: selectedCompanyId,
          decoration: const InputDecoration(labelText: 'Empresa'),
          items: companies
              .map(
                (company) => DropdownMenuItem<String>(
                  value: company.id,
                  child: Text(company.name),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onCompanyChanged(value);
            }
          },
        ),
      ),
    );
  }
}

class _CustomerSummarySurface extends StatelessWidget {
  const _CustomerSummarySurface({required this.customer});

  final AdminCrmCustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    final contactBits = [
      if ((customer.phone ?? '').isNotEmpty) customer.phone!,
      if ((customer.address ?? '').isNotEmpty) customer.address!,
    ];

    return AdminSurface(
      title: customer.name,
      subtitle: contactBits.isEmpty
          ? 'Cliente CRM sem contato cadastrado.'
          : contactBits.join(' | '),
      trailing: Chip(label: Text(customer.isActive ? 'Ativo' : 'Inativo')),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MutedPill(label: 'UUID local ${customer.localUuid}'),
          _MutedPill(
            label:
                'Atualizado em ${AdminFormatters.formatDateTime(customer.updatedAt)}',
          ),
          _MutedPill(
            label: customer.operationalNotes == null
                ? 'Sem observacao operacional'
                : 'Observacao operacional disponivel',
          ),
          _MutedPill(
            label: customer.tags.isEmpty
                ? 'Sem tags CRM'
                : customer.tags.map((tag) => tag.label).join(', '),
          ),
        ],
      ),
    );
  }
}

class _CommercialSummaryGrid extends StatelessWidget {
  const _CommercialSummaryGrid({required this.summary});

  final AdminCrmCommercialSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricItem(
        label: 'Vendas',
        value: '${summary.totalSalesCount}',
        helper: 'Venda(s) identificadas no backend',
      ),
      _MetricItem(
        label: 'Receita',
        value: AdminFormatters.formatCurrencyFromCents(
          summary.totalRevenueCents,
        ),
        helper: 'Total consolidado por cliente',
      ),
      _MetricItem(
        label: 'Margem',
        value: AdminFormatters.formatCurrencyFromCents(
          summary.totalProfitCents,
        ),
        helper: 'Receita menos custo espelhado',
      ),
      _MetricItem(
        label: 'Fiado recebido',
        value: AdminFormatters.formatCurrencyFromCents(
          summary.totalFiadoPaymentsCents,
        ),
        helper: 'Recebimentos vinculados a vendas do cliente',
      ),
      _MetricItem(
        label: 'Tarefas abertas',
        value: '${summary.openTasksCount}',
        helper: '${summary.overdueTasksCount} atrasada(s)',
      ),
      _MetricItem(
        label: 'Ultimo CRM',
        value: AdminFormatters.formatDateTime(summary.lastCrmEventAt),
        helper: 'Ultimo evento comercial registrado',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1400
            ? 3
            : constraints.maxWidth >= 900
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2.4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return AdminSurface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.helper,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TagsSurface extends StatelessWidget {
  const _TagsSurface({
    required this.customer,
    required this.controller,
    required this.isSaving,
    required this.onApply,
    required this.onClear,
  });

  final AdminCrmCustomerSummary customer;
  final TextEditingController controller;
  final bool isSaving;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Tags CRM',
      subtitle:
          'Aplique tags simples no customer master remoto. A observacao operacional continua separada.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customer.tags.isEmpty)
            Text(
              'Nenhuma tag CRM aplicada.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: customer.tags
                  .map((tag) => Chip(label: Text(tag.label)))
                  .toList(growable: false),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Novas tags',
              hintText: 'vip, recorrente, campanha sexta',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: isSaving ? null : onApply,
                icon: const Icon(Icons.sell_rounded),
                label: Text(isSaving ? 'Salvando...' : 'Salvar tags'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: isSaving ? null : onClear,
                child: const Text('Limpar tags'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteComposerSurface extends StatelessWidget {
  const _NoteComposerSurface({
    required this.controller,
    required this.isSaving,
    required this.onCreate,
  });

  final TextEditingController controller;
  final bool isSaving;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Nova nota CRM',
      subtitle:
          'Registre contexto comercial sem sobrescrever a observacao operacional simples usada no app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Nota',
              hintText: 'Cliente pediu retorno para a campanha de sexta.',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isSaving ? null : onCreate,
            icon: const Icon(Icons.note_add_rounded),
            label: Text(isSaving ? 'Salvando...' : 'Criar nota'),
          ),
        ],
      ),
    );
  }
}

class _TaskComposerSurface extends StatelessWidget {
  const _TaskComposerSurface({
    required this.titleController,
    required this.descriptionController,
    required this.dueDateController,
    required this.isSaving,
    required this.onCreate,
  });

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController dueDateController;
  final bool isSaving;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Nova tarefa CRM',
      subtitle:
          'Acompanhe follow-up comercial no cloud sem levar peso de CRM para a operacao do caixa.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Titulo',
              hintText: 'Ligar e confirmar interesse',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descriptionController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Descricao',
              hintText: 'Anotar contexto do follow-up comercial.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: dueDateController,
            decoration: const InputDecoration(
              labelText: 'Prazo',
              hintText: 'YYYY-MM-DD',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isSaving ? null : onCreate,
            icon: const Icon(Icons.task_alt_rounded),
            label: Text(isSaving ? 'Salvando...' : 'Criar tarefa'),
          ),
        ],
      ),
    );
  }
}

class _NotesSurface extends StatelessWidget {
  const _NotesSurface({required this.notes});

  final List<AdminCrmNote> notes;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Notas CRM',
      subtitle:
          '${notes.length} nota(s) comerciais registradas para o cliente.',
      child: notes.isEmpty
          ? const Text('Ainda nao ha notas CRM para este cliente.')
          : Column(
              children: notes
                  .map(
                    (note) => _RecordCard(
                      title: note.author?.name ?? 'Autor nao identificado',
                      subtitle: AdminFormatters.formatDateTime(note.createdAt),
                      body: note.body,
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _TasksSurface extends StatelessWidget {
  const _TasksSurface({required this.tasks});

  final List<AdminCrmTask> tasks;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Tarefas CRM',
      subtitle:
          '${tasks.length} tarefa(s) comerciais registradas para o cliente.',
      child: tasks.isEmpty
          ? const Text('Ainda nao ha tarefas CRM para este cliente.')
          : Column(
              children: tasks
                  .map(
                    (task) => _RecordCard(
                      title: task.title,
                      subtitle:
                          '${AdminFormatters.formatCrmTaskStatus(task.status)} | prazo ${AdminFormatters.formatDate(task.dueAt)}',
                      body: task.description ?? 'Sem descricao complementar.',
                      trailing: Chip(
                        label: Text(
                          AdminFormatters.formatCrmTaskStatus(task.status),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _TimelineSurface extends StatelessWidget {
  const _TimelineSurface({required this.timeline, required this.customerName});

  final AdminPaginatedResult<AdminCrmTimelineEvent> timeline;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Timeline do cliente',
      subtitle:
          'Eventos CRM e sinais comerciais espelhados para $customerName no backend.',
      child: timeline.items.isEmpty
          ? const Text('Ainda nao ha eventos na timeline deste cliente.')
          : Column(
              children: timeline.items
                  .map((event) => _TimelineCard(event: event))
                  .toList(growable: false),
            ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.event});

  final AdminCrmTimelineEvent event;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                label: Text(
                  AdminFormatters.formatCrmTimelineEventType(event.eventType),
                ),
              ),
              Chip(
                label: Text(
                  event.source == 'crm' ? 'CRM' : 'Espelho comercial',
                ),
              ),
              Text(
                AdminFormatters.formatDateTime(event.occurredAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            event.headline,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if ((event.body ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(event.body!),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (event.actor != null)
                Text(
                  'Ator: ${event.actor!.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (event.amountCents != null)
                Text(
                  'Valor: ${AdminFormatters.formatCurrencyFromCents(event.amountCents!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.title,
    required this.subtitle,
    required this.body,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          Text(body),
        ],
      ),
    );
  }
}

class _MetricItem {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;
}

class _MutedPill extends StatelessWidget {
  const _MutedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
