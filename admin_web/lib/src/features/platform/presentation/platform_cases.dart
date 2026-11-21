import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_providers.dart';
import '../data/platform_api.dart';
import 'platform_overview.dart';
import 'platform_search.dart';
import 'platform_widgets.dart';

const _caseStates = ['OPEN', 'IN_PROGRESS', 'WAITING', 'RESOLVED'];
const _priorities = ['CRITICAL', 'HIGH', 'NORMAL', 'LOW'];

class PlatformCasesPage extends ConsumerWidget {
  const PlatformCasesPage({super.key, this.companyId, this.evidenceKey});
  final String? companyId;
  final String? evidenceKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = platformLocation(context, '/support/cases');
    final query = location.queryParameters;
    final company = companyId ?? query['companyId'];
    final page = int.tryParse(query['page'] ?? '') ?? 1;
    final status = query['status'] ?? 'active';
    final resource = platformResource('/admin/support/cases', {
      'page': '$page',
      'pageSize': '20',
      'companyId': company,
      'status': status == 'all' ? null : status,
      'mine': query['mine'],
      'search': query['search'],
    });
    final capabilities = ref.watch(platformCapabilitiesProvider).valueOrNull;
    void filter(Map<String, String?> changes) => platformNavigate(
      context,
      platformResource(location.path, {...query, 'page': '1', ...changes}),
    );
    return PlatformPage(
      storageKey: resource,
      children: [
        PlatformHeader(
          title: 'Chamados internos',
          subtitle: 'Acompanhe o problema, o responsável e a solução.',
          actions: [
            if (platformAllowsAction(
              capabilities,
              'admin.support.manage',
              companyId: company,
            ))
              FilledButton.icon(
                onPressed: () =>
                    showPlatformCaseCreation(context, companyId: company),
                icon: const Icon(Icons.add),
                label: const Text('Novo chamado'),
              ),
            IconButton(
              tooltip: 'Atualizar chamados',
              onPressed: () =>
                  ref.invalidate(platformResourceProvider(resource)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: ['active', 'all', ..._caseStates].contains(status)
                    ? status
                    : 'active',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Situação'),
                items: [
                  const DropdownMenuItem(
                    value: 'active',
                    child: Text('Todos em aberto'),
                  ),
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('Todos os chamados'),
                  ),
                  for (final value in _caseStates)
                    DropdownMenuItem(
                      value: value,
                      child: Text(platformStatus(value)),
                    ),
                ],
                onChanged: (value) => filter({'status': value}),
              ),
            ),
            FilterChip(
              label: const Text('Sob minha responsabilidade'),
              selected: query['mine'] == 'true',
              onSelected: (selected) =>
                  filter({'mine': selected ? 'true' : null}),
            ),
            if (company != null)
              InputChip(
                label: const Text('Empresa selecionada'),
                onDeleted: companyId == null
                    ? () => filter({'companyId': null})
                    : null,
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final item = await choosePlatformCompany(context);
                if (context.mounted && item != null) {
                  filter({
                    'companyId': platformText(
                      item['companyId'] ?? item['id'],
                      '',
                    ),
                  });
                }
              },
              icon: const Icon(Icons.apartment_outlined),
              label: const Text('Filtrar empresa'),
            ),
          ],
        ),
        TextFormField(
          key: ValueKey(query['search']),
          initialValue: query['search'],
          decoration: const InputDecoration(
            labelText: 'Pesquisar chamados',
            hintText: 'Digite um assunto e pressione Enter',
            suffixIcon: Icon(Icons.search),
          ),
          onFieldSubmitted: (value) =>
              filter({'search': value.trim().isEmpty ? null : value.trim()}),
        ),
        PlatformPanel(
          title: 'Fila de atendimento',
          child: PlatformResourceView(
            resource: resource,
            builder: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlatformCaseRows(items: platformItems(data['items'])),
                const SizedBox(height: 16),
                PlatformPager(
                  page: page,
                  total: platformInt(data['total']),
                  pageSize: 20,
                  onPage: (next) => filter({'page': '$next'}),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showPlatformCaseCreation(
  BuildContext context, {
  String? companyId,
  String? companyName,
  PlatformMap? evidence,
}) async {
  final created = await showDialog<PlatformMap>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CaseCreationDialog(
      companyId: companyId,
      companyName: companyName,
      evidence: evidence,
    ),
  );
  if (!context.mounted || created == null) return;
  platformNavigate(
    context,
    '/support/cases/${Uri.encodeComponent(platformText(created['id'], ''))}',
  );
}

class _CaseCreationDialog extends ConsumerStatefulWidget {
  const _CaseCreationDialog({this.companyId, this.companyName, this.evidence});
  final String? companyId;
  final String? companyName;
  final PlatformMap? evidence;
  @override
  ConsumerState<_CaseCreationDialog> createState() =>
      _CaseCreationDialogState();
}

class _CaseCreationDialogState extends ConsumerState<_CaseCreationDialog> {
  final _subject = TextEditingController();
  final _description = TextEditingController();
  final _requestKey = platformRequestKey();
  String? _companyId;
  String? _companyName;
  String _priority = 'NORMAL';
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _companyId = widget.companyId;
    _companyName = widget.companyName;
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_companyId == null ||
        _subject.text.trim().length < 3 ||
        _description.text.trim().length < 3) {
      setState(
        () => _error =
            'Selecione a empresa e preencha assunto e descrição com pelo menos três caracteres.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(platformApiProvider)
          .post('/admin/support/cases', {
            'companyId': _companyId,
            'subject': _subject.text.trim(),
            'description': _description.text.trim(),
            'priority': _priority,
            'requestKey': _requestKey,
            if (widget.evidence != null) 'evidence': widget.evidence,
          });
      if (!mounted) return;
      Navigator.of(context).pop(platformMap(response['item']));
    } catch (error) {
      if (mounted) setState(() => _error = platformError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Novo chamado interno'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _companyName ??
                  (_companyId == null
                      ? 'Escolha a empresa atendida'
                      : 'Empresa: $_companyId'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final item = await choosePlatformCompany(context);
                      if (mounted && item != null) {
                        setState(() {
                          _companyId = platformText(
                            item['companyId'] ?? item['id'],
                            '',
                          );
                          _companyName = platformText(item['label']);
                        });
                      }
                    },
              icon: const Icon(Icons.search),
              label: const Text('Escolher empresa'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _subject,
              enabled: !_busy,
              maxLength: 180,
              decoration: const InputDecoration(labelText: 'Assunto'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              enabled: !_busy,
              minLines: 3,
              maxLines: 6,
              maxLength: 8000,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                hintText: 'Descreva o problema sem incluir senhas ou tokens.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Prioridade'),
              items: [
                for (final priority in _priorities)
                  DropdownMenuItem(
                    value: priority,
                    child: Text(platformStatus(priority)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _priority = value ?? 'NORMAL'),
            ),
            if (widget.evidence != null) ...[
              const SizedBox(height: 12),
              const Text(
                'A evidência deste problema será vinculada. Um chamado ativo existente será reaproveitado.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('Criar chamado'),
      ),
    ],
  );
}

class PlatformCaseDetailPage extends ConsumerStatefulWidget {
  const PlatformCaseDetailPage({super.key, required this.caseId});
  final String caseId;
  @override
  ConsumerState<PlatformCaseDetailPage> createState() =>
      _PlatformCaseDetailPageState();
}

class _PlatformCaseDetailPageState
    extends ConsumerState<PlatformCaseDetailPage> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  String get _resource =>
      '/admin/support/cases/${Uri.encodeComponent(widget.caseId)}';
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _mutate(
    PlatformMap item,
    PlatformMap change, {
    bool note = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = {
        'expectedRevision': platformInt(item['revision']),
        ...change,
      };
      if (note) {
        await ref.read(platformApiProvider).post('$_resource/notes', body);
      } else {
        await ref.read(platformApiProvider).patch(_resource, body);
      }
      if (!mounted) return;
      if (note) _note.clear();
      ref.invalidate(platformResourceProvider(_resource));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chamado atualizado.')));
    } catch (error) {
      if (mounted) setState(() => _error = platformError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeState(PlatformMap item) async {
    final response = await showDialog<PlatformMap>(
      context: context,
      builder: (_) => _CaseStateDialog(item: item),
    );
    if (response != null && mounted) await _mutate(item, response);
  }

  Future<void> _assign(PlatformMap item) async {
    final result = await showDialog<PlatformMap>(
      context: context,
      builder: (_) =>
          _AssigneeDialog(companyId: platformText(item['companyId'], '')),
    );
    if (result != null && mounted) {
      await _mutate(item, {'assigneeId': result['id']});
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(platformCapabilitiesProvider).valueOrNull;
    final data = ref.watch(platformResourceProvider(_resource));
    return PlatformPage(
      storageKey: _resource,
      children: [
        PlatformHeader(
          title: 'Atendimento',
          subtitle: 'Evidências, acompanhamento e resultado em um único lugar.',
          actions: [
            TextButton.icon(
              onPressed: () => platformNavigate(context, '/support/cases'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Chamados'),
            ),
            IconButton(
              tooltip: 'Atualizar chamado',
              onPressed: _busy
                  ? null
                  : () => ref.invalidate(platformResourceProvider(_resource)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          PlatformState(
            error: true,
            message: _error!,
            onRetry: () {
              ref.invalidate(platformResourceProvider(_resource));
              setState(() => _error = null);
            },
          ),
        data.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => PlatformState(
            error: true,
            message: platformError(error),
            onRetry: () => ref.invalidate(platformResourceProvider(_resource)),
          ),
          data: (data) {
            final item = platformMap(data['item']);
            final companyId = platformText(item['companyId'], '');
            final canManage = platformAllowsAction(
              capabilities,
              'admin.support.manage',
              companyId: companyId,
            );
            final assignee = platformMap(item['assignee']);
            final actorId = ref
                .watch(adminAuthControllerProvider)
                .session
                ?.user
                .id;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlatformPanel(
                  title: platformText(item['subject']),
                  subtitle:
                      '${platformText(item['companyName'])} · ${platformStatus(platformText(item['priority']))} · ${platformStatus(platformText(item['status']))}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        platformText(item['description'], 'Sem descrição.'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Responsável: ${platformText(assignee['name'], 'Sem responsável')}',
                      ),
                      Text(
                        'Atualizado ${platformDate(item['updatedAt'])} · Revisão ${platformInt(item['revision'])}',
                      ),
                      if (item['resolution'] != null) ...[
                        const SizedBox(height: 12),
                        Text('Resultado: ${platformText(item['resolution'])}'),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => platformNavigate(
                              context,
                              '/companies/$companyId/support',
                            ),
                            icon: const Icon(Icons.apartment_outlined),
                            label: const Text('Abrir empresa'),
                          ),
                          if (canManage) ...[
                            if (assignee['id'] != actorId && actorId != null)
                              FilledButton.tonalIcon(
                                onPressed: _busy
                                    ? null
                                    : () => _mutate(item, {
                                        'assigneeId': actorId,
                                      }),
                                icon: const Icon(
                                  Icons.person_add_alt_1_outlined,
                                ),
                                label: const Text('Assumir chamado'),
                              ),
                            OutlinedButton(
                              onPressed: _busy ? null : () => _assign(item),
                              child: const Text('Transferir responsável'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _changeState(item),
                              child: const Text('Alterar situação'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final value = await showDialog<String>(
                                        context: context,
                                        builder: (dialogContext) =>
                                            SimpleDialog(
                                              title: const Text(
                                                'Prioridade do chamado',
                                              ),
                                              children: [
                                                for (final value in _priorities)
                                                  SimpleDialogOption(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          dialogContext,
                                                        ).pop(value),
                                                    child: Text(
                                                      platformStatus(value),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                      );
                                      if (value != null && mounted) {
                                        await _mutate(item, {
                                          'priority': value,
                                        });
                                      }
                                    },
                              child: const Text('Alterar prioridade'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                PlatformPanel(
                  title: 'Histórico do atendimento',
                  child: platformItems(item['events']).isEmpty
                      ? const PlatformState(
                          message: 'Nenhuma anotação adicional neste chamado.',
                        )
                      : Column(
                          children: [
                            for (final event in platformItems(item['events']))
                              PlatformRow(
                                title: platformText(
                                  platformMap(event['author'])['name'],
                                  'Administrador',
                                ),
                                subtitle:
                                    '${platformDate(event['createdAt'])} · ${platformText(event['type'])}\n${platformText(event['body'], '')}',
                              ),
                          ],
                        ),
                ),
                if (canManage) ...[
                  const SizedBox(height: 20),
                  PlatformPanel(
                    title: 'Registrar acompanhamento',
                    subtitle:
                        'Anotações internas. Não inclua credenciais ou dados de pagamento.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _note,
                          enabled: !_busy,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: 8000,
                          decoration: const InputDecoration(
                            labelText: 'Anotação',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () {
                                  if (_note.text.trim().isEmpty) {
                                    setState(
                                      () => _error =
                                          'Escreva uma anotação antes de salvar.',
                                    );
                                    return;
                                  }
                                  _mutate(item, {
                                    'body': _note.text.trim(),
                                  }, note: true);
                                },
                          icon: const Icon(Icons.add_comment_outlined),
                          label: const Text('Salvar anotação'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AssigneeDialog extends ConsumerWidget {
  const _AssigneeDialog({required this.companyId});
  final String companyId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
    title: const Text('Responsável pelo chamado'),
    content: SizedBox(
      width: 420,
      height: 320,
      child: PlatformResourceView(
        resource: '/admin/support/cases/assignees?companyId=$companyId',
        builder: (data) => ListView(
          children: [
            ListTile(
              title: const Text('Sem responsável'),
              onTap: () =>
                  Navigator.of(context).pop(<String, dynamic>{'id': null}),
            ),
            for (final actor in platformItems(data['items']))
              ListTile(
                title: Text(platformText(actor['name'])),
                onTap: () => Navigator.of(context).pop(actor),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
    ],
  );
}

class _CaseStateDialog extends StatefulWidget {
  const _CaseStateDialog({required this.item});
  final PlatformMap item;
  @override
  State<_CaseStateDialog> createState() => _CaseStateDialogState();
}

class _CaseStateDialogState extends State<_CaseStateDialog> {
  late String _status;
  final _resolution = TextEditingController();
  String? _error;
  @override
  void initState() {
    super.initState();
    _status = platformText(widget.item['status'], 'OPEN');
  }

  @override
  void dispose() {
    _resolution.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Alterar situação'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: [
                for (final value in _caseStates)
                  DropdownMenuItem(
                    value: value,
                    child: Text(platformStatus(value)),
                  ),
              ],
              onChanged: (value) => setState(() => _status = value ?? 'OPEN'),
            ),
            if (_status == 'RESOLVED') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _resolution,
                minLines: 3,
                maxLines: 6,
                maxLength: 8000,
                decoration: const InputDecoration(
                  labelText: 'Resultado do atendimento',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_status == 'RESOLVED' && _resolution.text.trim().isEmpty) {
            setState(() => _error = 'Descreva o resultado antes de resolver.');
            return;
          }
          Navigator.of(context).pop(<String, dynamic>{
            'status': _status,
            if (_status == 'RESOLVED') 'resolution': _resolution.text.trim(),
          });
        },
        child: const Text('Salvar situação'),
      ),
    ],
  );
}
