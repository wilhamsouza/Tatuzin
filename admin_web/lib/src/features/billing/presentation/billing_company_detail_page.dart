import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/admin_providers.dart';
import '../../../core/models/admin_billing_models.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/network/admin_api_client.dart';
import '../../../core/utils/admin_formatters.dart';
import '../../../core/widgets/admin_confirmation_dialog.dart';
import '../../../core/widgets/admin_surface.dart';

const _cancelLocalWarning =
    'Esta ação não cancela Mercado Pago. Ela aplica apenas correção local administrativa.';

class BillingCompanyDetailPage extends ConsumerStatefulWidget {
  const BillingCompanyDetailPage({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<BillingCompanyDetailPage> createState() =>
      _BillingCompanyDetailPageState();
}

class _BillingCompanyDetailPageState
    extends ConsumerState<BillingCompanyDetailPage> {
  int _eventsPage = 1;
  int _sessionsPage = 1;
  bool _isActionRunning = false;

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(
      adminBillingCompanyStatusProvider(widget.companyId),
    );
    final eventsQuery = AdminBillingListQuery(
      companyId: widget.companyId,
      page: _eventsPage,
      pageSize: 10,
    );
    final sessionsQuery = AdminBillingListQuery(
      companyId: widget.companyId,
      page: _sessionsPage,
      pageSize: 10,
    );
    final eventsAsync = ref.watch(adminBillingEventsProvider(eventsQuery));
    final sessionsAsync = ref.watch(
      adminBillingCheckoutSessionsProvider(sessionsQuery),
    );

    return statusAsync.when(
      data: (status) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminSurface(
              title: 'Billing de ${status.companyName}',
              subtitle:
                  'Detalhe interno de plataforma. Não exponha estes dados ao owner.',
              child: _BillingStatusSection(
                status: status,
                onRefresh: () => _refreshBilling(status),
                onForcePlan: () => _forcePlan(status),
                onCancelLocal: () => _cancelLocal(status),
                isActionRunning: _isActionRunning,
              ),
            ),
            const SizedBox(height: 24),
            _InvoicesSurface(invoices: status.invoices),
            const SizedBox(height: 24),
            eventsAsync.when(
              data: (events) => _EventsSurface(
                events: events,
                onPrevious: events.pagination.hasPrevious
                    ? () => setState(() => _eventsPage--)
                    : null,
                onNext: events.pagination.hasNext
                    ? () => setState(() => _eventsPage++)
                    : null,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AdminSurface(
                title: 'Eventos de billing',
                subtitle: error.toString(),
                child: FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(adminBillingEventsProvider(eventsQuery)),
                  child: const Text('Tentar novamente'),
                ),
              ),
            ),
            const SizedBox(height: 24),
            sessionsAsync.when(
              data: (sessions) => _CheckoutSessionsSurface(
                sessions: sessions,
                onPrevious: sessions.pagination.hasPrevious
                    ? () => setState(() => _sessionsPage--)
                    : null,
                onNext: sessions.pagination.hasNext
                    ? () => setState(() => _sessionsPage++)
                    : null,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AdminSurface(
                title: 'Checkout sessions',
                subtitle: error.toString(),
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(
                    adminBillingCheckoutSessionsProvider(sessionsQuery),
                  ),
                  child: const Text('Tentar novamente'),
                ),
              ),
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AdminSurface(
        title: 'Não foi possível carregar billing da empresa',
        subtitle: error.toString(),
        child: FilledButton.tonal(
          onPressed: () => ref.invalidate(
            adminBillingCompanyStatusProvider(widget.companyId),
          ),
          child: const Text('Tentar novamente'),
        ),
      ),
    );
  }

  Future<void> _refreshBilling(AdminBillingCompanyStatus status) async {
    final reason = await _askReason(
      title: 'Motivo do refresh',
      hint: 'Explique por que a reconciliação será forçada',
    );
    if (reason == null || !mounted) {
      return;
    }
    final confirmed = await showAdminConfirmationDialog(
      context: context,
      title: 'Confirmar refresh de billing',
      message:
          'A ação vai consultar o Mercado Pago pelo fluxo seguro do backend.',
      details: [
        'Empresa: ${status.companyName}',
        'Mercado Pago será consultado: sim',
        'Motivo: $reason',
      ],
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _runAction(
      () => ref
          .read(adminApiServiceProvider)
          .refreshBillingCompany(companyId: widget.companyId, reason: reason),
      successMessage: 'Refresh de billing solicitado.',
    );
  }

  Future<void> _forcePlan(AdminBillingCompanyStatus status) async {
    final input = await _showForcePlanDialog();
    if (input == null || !mounted) {
      return;
    }
    final confirmed = await showAdminConfirmationDialog(
      context: context,
      title: 'Confirmar force-plan',
      message:
          'Esta correção altera a licença local pelo fluxo administrativo auditado.',
      isDestructive: true,
      confirmLabel: 'Aplicar force-plan',
      details: [
        'Empresa: ${status.companyName}',
        'Plano alvo: ${input.plan}',
        'Status administrativo: ${input.status ?? 'preservar'}',
        'currentPeriodEnd: ${input.currentPeriodEnd?.toIso8601String() ?? 'não informado'}',
        'clearProvider: ${input.clearProvider ? 'sim' : 'não'}',
        'Mercado Pago será afetado: não',
        'Motivo: ${input.reason}',
      ],
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _runAction(
      () => ref
          .read(adminApiServiceProvider)
          .forceBillingPlan(
            companyId: widget.companyId,
            plan: input.plan,
            status: input.status,
            reason: input.reason,
            currentPeriodEnd: input.currentPeriodEnd,
            clearProvider: input.clearProvider,
          ),
      successMessage: 'Force-plan aplicado.',
    );
  }

  Future<void> _cancelLocal(AdminBillingCompanyStatus status) async {
    final input = await _showCancelLocalDialog();
    if (input == null || !mounted) {
      return;
    }
    final confirmed = await showAdminConfirmationDialog(
      context: context,
      title: 'Confirmar cancel-local',
      message: _cancelLocalWarning,
      isDestructive: true,
      confirmLabel: 'Aplicar cancel-local',
      details: [
        'Empresa: ${status.companyName}',
        'effective: ${input.effective}',
        'Mercado Pago será afetado: não',
        'Motivo: ${input.reason}',
      ],
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _runAction(
      () => ref
          .read(adminApiServiceProvider)
          .cancelBillingLocal(
            companyId: widget.companyId,
            reason: input.reason,
            effective: input.effective,
          ),
      successMessage: 'Cancel-local aplicado.',
    );
  }

  Future<void> _runAction(
    Future<AdminBillingActionResult> Function() action, {
    required String successMessage,
  }) async {
    if (_isActionRunning) {
      return;
    }
    setState(() => _isActionRunning = true);
    try {
      final result = await action();
      ref.read(adminRefreshTickProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message ?? successMessage)));
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isActionRunning = false);
      }
    }
  }

  Future<String?> _askReason({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Motivo obrigatório',
                  hintText: hint,
                  errorText: error,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final reason = controller.text.trim();
                    if (reason.isEmpty) {
                      setDialogState(() {
                        error = 'Informe um motivo.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(reason);
                  },
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );
    _disposeDialogControllers(controller);
    return result;
  }

  Future<_ForcePlanInput?> _showForcePlanDialog() async {
    var plan = 'PRO';
    String? status = 'ACTIVE';
    var clearProvider = false;
    final currentPeriodEndController = TextEditingController();
    final reasonController = TextEditingController();
    String? error;
    final result = await showDialog<_ForcePlanInput>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Force-plan'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: plan,
                        decoration: const InputDecoration(labelText: 'Plano'),
                        items: const [
                          DropdownMenuItem(value: 'FREE', child: Text('FREE')),
                          DropdownMenuItem(
                            value: 'BASIC',
                            child: Text('BASIC'),
                          ),
                          DropdownMenuItem(value: 'PRO', child: Text('PRO')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => plan = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: status,
                        decoration: const InputDecoration(
                          labelText: 'Status administrativo',
                        ),
                        items: const [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Preservar'),
                          ),
                          DropdownMenuItem(
                            value: 'ACTIVE',
                            child: Text('ACTIVE'),
                          ),
                          DropdownMenuItem(
                            value: 'EXPIRED',
                            child: Text('EXPIRED'),
                          ),
                          DropdownMenuItem(
                            value: 'CANCELLED',
                            child: Text('CANCELLED'),
                          ),
                          DropdownMenuItem(
                            value: 'PAST_DUE',
                            child: Text('PAST_DUE'),
                          ),
                        ],
                        onChanged: (value) => setDialogState(() {
                          status = value;
                        }),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: clearProvider,
                        title: const Text('Limpar vínculo provider na licença'),
                        subtitle: const Text(
                          'Não altera sessões, eventos ou faturas.',
                        ),
                        onChanged: (value) => setDialogState(() {
                          clearProvider = value == true;
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: currentPeriodEndController,
                        decoration: const InputDecoration(
                          labelText: 'currentPeriodEnd opcional',
                          hintText: '2026-05-31T23:59:59.000Z',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Motivo obrigatório',
                          errorText: error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    final currentPeriodEndText = currentPeriodEndController.text
                        .trim();
                    final currentPeriodEnd = currentPeriodEndText.isEmpty
                        ? null
                        : DateTime.tryParse(currentPeriodEndText);
                    if (reason.isEmpty) {
                      setDialogState(() => error = 'Informe um motivo.');
                      return;
                    }
                    if (currentPeriodEndText.isNotEmpty &&
                        currentPeriodEnd == null) {
                      setDialogState(
                        () => error =
                            'Informe currentPeriodEnd em formato ISO válido.',
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _ForcePlanInput(
                        plan: plan,
                        status: status,
                        currentPeriodEnd: currentPeriodEnd,
                        clearProvider: clearProvider,
                        reason: reason,
                      ),
                    );
                  },
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );
    _disposeDialogControllers(currentPeriodEndController, reasonController);
    return result;
  }

  Future<_CancelLocalInput?> _showCancelLocalDialog() async {
    var effective = 'period_end';
    final reasonController = TextEditingController();
    String? error;
    final result = await showDialog<_CancelLocalInput>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cancel-local'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(_cancelLocalWarning),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: effective,
                      decoration: const InputDecoration(labelText: 'Effective'),
                      items: const [
                        DropdownMenuItem(
                          value: 'period_end',
                          child: Text('period_end'),
                        ),
                        DropdownMenuItem(value: 'now', child: Text('now')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => effective = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Motivo obrigatório',
                        errorText: error,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    if (reason.isEmpty) {
                      setDialogState(() => error = 'Informe um motivo.');
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _CancelLocalInput(reason: reason, effective: effective),
                    );
                  },
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );
    _disposeDialogControllers(reasonController);
    return result;
  }
}

void _disposeDialogControllers(TextEditingController first, [
  TextEditingController? second,
]) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    first.dispose();
    second?.dispose();
  });
}

class _BillingStatusSection extends StatelessWidget {
  const _BillingStatusSection({
    required this.status,
    required this.onRefresh,
    required this.onForcePlan,
    required this.onCancelLocal,
    required this.isActionRunning,
  });

  final AdminBillingCompanyStatus status;
  final VoidCallback onRefresh;
  final VoidCallback onForcePlan;
  final VoidCallback onCancelLocal;
  final bool isActionRunning;

  @override
  Widget build(BuildContext context) {
    final billing = status.billing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: isActionRunning ? null : onRefresh,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Refresh'),
            ),
            FilledButton.tonalIcon(
              onPressed: isActionRunning ? null : onForcePlan,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Force-plan'),
            ),
            FilledButton.tonalIcon(
              onPressed: isActionRunning ? null : onCancelLocal,
              icon: const Icon(Icons.block_rounded),
              label: const Text('Cancel-local'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 32,
          runSpacing: 12,
          children: [
            _DetailItem('Plano', status.license?.plan ?? 'Sem licença'),
            _DetailItem('Status', status.license?.status ?? 'Não informado'),
            _DetailItem('Provider', billing.provider ?? 'Não informado'),
            _DetailItem(
              'Provider mascarado',
              billing.maskedProviderSubscriptionId ?? 'Sem assinatura',
            ),
            _DetailItem(
              'Período atual',
              AdminFormatters.formatDate(billing.currentPeriodEnd),
            ),
            _DetailItem(
              'Próxima cobrança',
              AdminFormatters.formatDate(billing.nextPaymentDate),
            ),
            _DetailItem(
              'Cancelamento agendado',
              billing.cancelAtPeriodEnd ? 'Sim' : 'Não',
            ),
            _DetailItem('Pending plan', billing.pendingPlan ?? 'Nenhum'),
            _DetailItem(
              'Billing status',
              billing.billingSubscriptionStatus ?? 'Não informado',
            ),
          ],
        ),
        if (billing.providerSubscriptionId?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dado interno de plataforma',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SelectableText(billing.providerSubscriptionId!),
                const SizedBox(height: 8),
                Text(
                  'Não copie automaticamente e não exponha ao owner.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EventsSurface extends StatelessWidget {
  const _EventsSurface({
    required this.events,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginatedResult<AdminBillingEvent> events;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Eventos sanitizados',
      subtitle: 'Payloads são sanitizados defensivamente antes de renderizar.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (events.items.isEmpty)
            const Text('Nenhum evento de billing encontrado.')
          else
            ...events.items.map(
              (event) => ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('${event.eventType} • ${event.status}'),
                subtitle: Text(
                  '${event.provider} • ${AdminFormatters.formatDateTime(event.createdAt)}',
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      formatSanitizedAdminJson(event.payload),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          _PaginationBar(
            pagination: events.pagination,
            itemLabel: 'eventos',
            onPrevious: onPrevious,
            onNext: onNext,
          ),
        ],
      ),
    );
  }
}

class _CheckoutSessionsSurface extends StatelessWidget {
  const _CheckoutSessionsSurface({
    required this.sessions,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginatedResult<AdminBillingCheckoutSession> sessions;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Checkout sessions',
      subtitle: 'URLs completas não são renderizadas nem copiáveis.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sessions.items.isEmpty)
            const Text('Nenhuma sessão de checkout encontrada.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Plano')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Provider')),
                  DataColumn(label: Text('Checkout URL mascarada')),
                  DataColumn(label: Text('Criada em')),
                ],
                rows: sessions.items
                    .map((session) {
                      return DataRow(
                        cells: [
                          DataCell(Text(session.plan)),
                          DataCell(Text(session.status)),
                          DataCell(Text(session.provider ?? 'Não informado')),
                          DataCell(
                            Text(session.checkoutUrl ?? 'Não informado'),
                          ),
                          DataCell(
                            Text(
                              AdminFormatters.formatDateTime(session.createdAt),
                            ),
                          ),
                        ],
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          const SizedBox(height: 12),
          _PaginationBar(
            pagination: sessions.pagination,
            itemLabel: 'sessões',
            onPrevious: onPrevious,
            onNext: onNext,
          ),
        ],
      ),
    );
  }
}

class _InvoicesSurface extends StatelessWidget {
  const _InvoicesSurface({required this.invoices});

  final List<AdminBillingInvoiceSummary> invoices;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Faturas resumidas',
      subtitle: 'Resumo interno quando houver BillingInvoice reconciliada.',
      child: invoices.isEmpty
          ? const Text('Nenhuma fatura registrada para esta empresa.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Valor')),
                  DataColumn(label: Text('Período')),
                  DataColumn(label: Text('Pago em')),
                  DataColumn(label: Text('Provider ID mascarado')),
                ],
                rows: invoices
                    .map((invoice) {
                      return DataRow(
                        cells: [
                          DataCell(Text(invoice.status)),
                          DataCell(Text(_formatMoney(invoice))),
                          DataCell(
                            Text(
                              '${AdminFormatters.formatDate(invoice.periodStart)} - ${AdminFormatters.formatDate(invoice.periodEnd)}',
                            ),
                          ),
                          DataCell(
                            Text(AdminFormatters.formatDate(invoice.paidAt)),
                          ),
                          DataCell(
                            Text(invoice.maskedProviderSubscriptionId ?? 'N/A'),
                          ),
                        ],
                      );
                    })
                    .toList(growable: false),
              ),
            ),
    );
  }

  static String _formatMoney(AdminBillingInvoiceSummary invoice) {
    final formatter = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: invoice.currency == 'BRL' ? 'R\$' : invoice.currency,
    );
    return formatter.format(invoice.amountCents / 100);
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.itemLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final AdminPaginationMeta pagination;
  final String itemLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Página ${pagination.page} • ${pagination.count} de ${pagination.total} $itemLabel',
        ),
        OutlinedButton.icon(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Anterior'),
        ),
        OutlinedButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Próxima'),
        ),
      ],
    );
  }
}

class _ForcePlanInput {
  const _ForcePlanInput({
    required this.plan,
    required this.status,
    required this.currentPeriodEnd,
    required this.clearProvider,
    required this.reason,
  });

  final String plan;
  final String? status;
  final DateTime? currentPeriodEnd;
  final bool clearProvider;
  final String reason;
}

class _CancelLocalInput {
  const _CancelLocalInput({required this.reason, required this.effective});

  final String reason;
  final String effective;
}
