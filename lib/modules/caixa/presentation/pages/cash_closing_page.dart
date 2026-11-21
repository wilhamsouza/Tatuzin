import '../../data/sqlite_cash_repository.dart';
import '../widgets/cash_workspace_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../domain/entities/cash_session.dart';
import '../../domain/entities/cash_closure_preview.dart';
import '../providers/cash_providers.dart';
import 'cash_count_page.dart';

class CashClosingPage extends ConsumerStatefulWidget {
  const CashClosingPage({super.key, required this.session});
  final CashSession session;
  @override
  ConsumerState<CashClosingPage> createState() => _CashClosingPageState();
}

class _CashClosingPageState extends ConsumerState<CashClosingPage> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  CashClosurePreview? _preview;
  CashCountResult? _count;
  Map<String, dynamic>? _calculatorDraft;
  CashSession? _closed;
  String? _error;
  bool _busy = true;
  Future<void> _writes = Future.value();
  String get _scope => 'close:${widget.session.uuid}';
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final draft = await ref
          .read(localCashRepositoryProvider)
          .loadDraft(_scope);
      if (!mounted) return;
      _amount.text = draft['amount'] as String? ?? '';
      if (draft['calculatorDraft'] is Map) {
        _calculatorDraft = Map<String, dynamic>.from(
          draft['calculatorDraft'] as Map,
        );
      }
      _reason.text = draft['reason'] as String? ?? '';
      _notes.text = draft['notes'] as String? ?? '';
      if (widget.session.workspaceVersion == 3) {
        final pending = await ref
            .read(localCashRepositoryProvider)
            .employeeClosureDetails(widget.session.uuid);
        if (_amount.text.isEmpty && pending['countedBalanceCents'] is int) {
          _amount.text = ((pending['countedBalanceCents'] as int) / 100)
              .toStringAsFixed(2);
        }
        if (_reason.text.isEmpty) {
          _reason.text = pending['reason'] as String? ?? '';
        }
        if (widget.session.isClosurePending) _closed = widget.session;
      }

      if (draft['count'] is Map) {
        _count = CashCountResult.fromJson(
          Map<String, dynamic>.from(draft['count'] as Map),
        );
      }
    } catch (e) {
      if (mounted) _error = 'Não foi possível recuperar a conferência: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  void _save() {
    final repository = ref.read(localCashRepositoryProvider);
    final value = {
      'amount': _amount.text,
      'reason': _reason.text,
      'notes': _notes.text,
      if (_count != null) 'count': _count!.toJson(),
      if (_calculatorDraft != null) 'calculatorDraft': _calculatorDraft,
    };
    _writes = _writes
        .then((_) => repository.saveDraft(_scope, value))
        .catchError((Object e) {
          if (mounted) {
            setState(() => _error = 'Não foi possível salvar o rascunho: $e');
          }
        });
  }

  void _changed(String _) {
    setState(() {
      _preview = null;
      _error = null;
    });
    _save();
  }

  Future<void> _reviewOrClose() async {
    if (_busy) return;
    final amount = parseCashAmount(_amount.text);
    if (amount == null) {
      setState(
        () =>
            _error = 'Informe o total contado. Use 0 para caixa sem dinheiro.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _writes;
      final repository = ref.read(localCashRepositoryProvider);
      if (_preview == null) {
        final preview = await repository.prepareClosure(widget.session.uuid);
        final requiredReason =
            preview.session.blindClosureEnabled ||
            amount != preview.session.expectedBalanceCents;
        if (requiredReason && _reason.text.trim().isEmpty) {
          if (mounted) {
            setState(() => _error = 'Informe o motivo da conferência.');
          }
          return;
        }
        if (mounted) setState(() => _preview = preview);
      } else {
        final closed = await repository.commitClosure(
          preview: _preview!,
          countedBalanceCents: amount,
          reason: _reason.text,
          notes: _notes.text,
          count: _count,
        );
        ref.read(appDataRefreshProvider.notifier).state++;
        if (mounted) setState(() => _closed = closed);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _preview = null;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final closed = _closed;
    final preview = _preview;
    final blind = widget.session.blindClosureEnabled;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          closed == null
              ? (widget.session.needsReview
                    ? 'Revisar conferência'
                    : 'Conferir e fechar caixa')
              : closed.isClosed
              ? 'Caixa fechado'
              : 'Fechamento pendente',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  Text(
                    'Caixa #${widget.session.id} · ${widget.session.operatorName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (closed != null) ...[
                    Icon(
                      closed.isClosed
                          ? Icons.check_circle_outline
                          : Icons.cloud_upload_outlined,
                      size: 48,
                    ),
                    Text(
                      closed.isClosed
                          ? 'Caixa fechado. A conferência final foi concluída.'
                          : 'Conferência salva. O fechamento aguarda todos os aparelhos do funcionário sincronizarem e confirmarem a mesma revisão. Abra o app em cada aparelho participante e sincronize até concluir. Se o saldo mudar, será necessário revisar a contagem e o motivo.',
                    ),
                    const SizedBox(height: 16),
                    if (closed.isClosed)
                      Text(
                        'Esperado: ${AppFormatters.currencyFromCents(closed.expectedBalanceCents)}',
                      ),
                    if (closed.isClosed && closed.countedBalanceCents != null)
                      Text(
                        'Contado: ${AppFormatters.currencyFromCents(closed.countedBalanceCents!)}',
                      ),
                    if (closed.isClosed && closed.differenceCents != null)
                      Text(
                        'Diferença: ${AppFormatters.currencyFromCents(closed.differenceCents!)}',
                      ),
                  ] else ...[
                    if (widget.session.needsReview)
                      const Text(
                        'Novas movimentações chegaram. Confira novamente a contagem e o motivo antes de enviar outra conferência.',
                      ),
                    Text(
                      blind
                          ? 'Conferência cega: informe o dinheiro físico. O resultado será mostrado após o fechamento.'
                          : 'Conte o dinheiro físico antes de revisar o fechamento.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('cash-counted-amount'),
                      controller: _amount,
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (v) {
                        _count = null;
                        _changed(v);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Total contado (R\$)',
                        hintText: 'Informe inclusive quando for zero',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _busy
                          ? null
                          : () async {
                              final count = await Navigator.of(context)
                                  .push<CashCountResult>(
                                    MaterialPageRoute(
                                      builder: (_) => CashWorkspaceTheme(
                                        child: CashCountPage(
                                          initialDraft: _calculatorDraft,
                                          onDraftChanged: (draft) {
                                            _calculatorDraft = draft;
                                            _save();
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                              if (!mounted || count == null) return;
                              _count = count;
                              _amount.text = (count.totalCents / 100)
                                  .toStringAsFixed(2);
                              _changed('');
                            },
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Contar cédulas e moedas'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _reason,
                      enabled: !_busy,
                      onChanged: _changed,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: blind
                            ? 'Motivo da conferência (obrigatório)'
                            : 'Motivo da diferença',
                        hintText: 'Obrigatório quando houver diferença',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notes,
                      enabled: !_busy,
                      onChanged: _changed,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Observações (opcional)',
                      ),
                    ),
                    if (preview != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Revise o fechamento',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  'Contado: ${AppFormatters.currencyFromCents(parseCashAmount(_amount.text)!)}',
                                ),
                                if (!blind) ...[
                                  Text(
                                    'Esperado: ${AppFormatters.currencyFromCents(preview.session.expectedBalanceCents)}',
                                  ),
                                  Text(
                                    'Diferença: ${AppFormatters.currencyFromCents(parseCashAmount(_amount.text)! - preview.session.expectedBalanceCents)}',
                                  ),
                                ],
                                const Text(
                                  'A conferência será salva mesmo sem conexão. O caixa só fecha após todos os aparelhos sincronizarem a mesma revisão.',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('cash-close-footer'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _busy
                      ? null
                      : closed != null
                      ? () => Navigator.of(context).pop(true)
                      : _reviewOrClose,
                  child: Text(
                    _busy
                        ? 'Aguarde…'
                        : closed != null
                        ? closed.isClosed
                              ? 'Concluir'
                              : 'Voltar ao caixa'
                        : preview == null
                        ? 'Revisar fechamento'
                        : 'Fechar caixa',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
