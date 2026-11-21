import '../../data/sqlite_cash_repository.dart';
import '../widgets/cash_workspace_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/cash_closure_preview.dart';
import '../../domain/entities/cash_session.dart';
import '../providers/cash_providers.dart';
import 'cash_count_page.dart';
import 'cash_closing_page.dart';

class CashOpeningPage extends ConsumerStatefulWidget {
  const CashOpeningPage({super.key, this.autoOpenedSession});
  final CashSession? autoOpenedSession;
  @override
  ConsumerState<CashOpeningPage> createState() => _CashOpeningPageState();
}

class _CashOpeningPageState extends ConsumerState<CashOpeningPage> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = true;
  CashCountResult? _count;
  Map<String, dynamic>? _calculatorDraft;
  String? _error;
  Future<void> _writes = Future.value();
  String get _scope => 'open:${widget.autoOpenedSession?.uuid ?? 'new'}';
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
      _notes.text = draft['notes'] as String? ?? '';
      if (draft['count'] is Map) {
        _count = CashCountResult.fromJson(
          Map<String, dynamic>.from(draft['count'] as Map),
        );
      }
    } catch (e) {
      _error = 'Não foi possível recuperar o rascunho: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  void _save(String _) {
    final repo = ref.read(localCashRepositoryProvider);
    final value = {
      'amount': _amount.text,
      'notes': _notes.text,
      if (_count != null) 'count': _count!.toJson(),
      if (_calculatorDraft != null) 'calculatorDraft': _calculatorDraft,
    };
    _writes = _writes.then((_) => repo.saveDraft(_scope, value)).catchError((
      Object e,
    ) {
      if (mounted) {
        setState(() => _error = 'Não foi possível salvar o rascunho: $e');
      }
    });
  }

  Future<void> _submit({bool closeAfterConfirmation = false}) async {
    if (_busy) return;
    final amount = parseCashAmount(_amount.text);
    if (amount == null) {
      setState(
        () => _error = closeAfterConfirmation
            ? 'Confira o troco inicial antes de fechar. Informe o valor, inclusive quando for zero.'
            : 'Informe o troco inicial. Use 0 se não houver troco.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _writes;
      final controller = ref.read(cashActionControllerProvider.notifier);
      late final CashSession confirmed;
      if (widget.autoOpenedSession != null) {
        confirmed = await controller.confirmAutoOpenedSession(
          initialFloatCents: amount,
          count: _count,
        );
      } else {
        confirmed = await controller.openSession(
          initialFloatCents: amount,
          notes: _notes.text,
          count: _count,
        );
      }
      await ref.read(localCashRepositoryProvider).saveDraft(_scope, {});
      if (confirmed.workspaceVersion == 3 && widget.autoOpenedSession == null) {
        final joined = await ref
            .read(localCashRepositoryProvider)
            .employeeOpenJoinedExisting();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              joined
                  ? 'Caixa existente recuperado; troco inicial preservado.'
                  : 'Caixa do funcionário aberto. O troco inicial foi registrado uma única vez.',
            ),
          ),
        );
      }
      if (!mounted) return;
      if (closeAfterConfirmation) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                CashWorkspaceTheme(child: CashClosingPage(session: confirmed)),
          ),
        );
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.autoOpenedSession == null
            ? 'Abrir caixa'
            : 'Conferir abertura automática',
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'O caixa é do funcionário e é compartilhado entre seus aparelhos. No primeiro acesso neste aparelho, conecte-se para recuperar ou abrir o caixa. Depois de associado, as movimentações podem ser registradas offline. O troco inicial é contado uma única vez; cédulas e moedas são opcionais.',
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('cash-opening-amount'),
                  controller: _amount,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (value) {
                    _count = null;
                    _save(value);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Troco inicial (R\$)',
                    hintText: 'Informe inclusive quando for zero',
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _busy
                      ? null
                      : () async {
                          final result = await Navigator.of(context)
                              .push<CashCountResult>(
                                MaterialPageRoute(
                                  builder: (_) => CashWorkspaceTheme(
                                    child: CashCountPage(
                                      useLabel: 'Usar total na abertura',
                                      initialDraft: _calculatorDraft,
                                      onDraftChanged: (draft) {
                                        _calculatorDraft = draft;
                                        _save('');
                                      },
                                    ),
                                  ),
                                ),
                              );
                          if (!mounted || result == null) return;
                          _count = result;
                          _amount.text = (result.totalCents / 100)
                              .toStringAsFixed(2);
                          _save('');
                        },
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Contar cédulas e moedas'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  enabled: !_busy,
                  onChanged: _save,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Observações (opcional)',
                  ),
                ),
                if (widget.autoOpenedSession != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _submit(closeAfterConfirmation: true),
                      child: const Text('Conferir e fechar este caixa'),
                    ),
                  ),
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : _submit,
                child: Text(
                  _busy
                      ? 'Aguarde…'
                      : widget.autoOpenedSession == null
                      ? 'Abrir caixa'
                      : 'Confirmar abertura',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
