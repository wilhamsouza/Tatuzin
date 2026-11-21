import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform_api.dart';
import 'platform_widgets.dart';

Future<void> showPlatformSearch(BuildContext context) async {
  final item = await showDialog<PlatformMap>(
    context: context,
    builder: (_) => const _PlatformSearchDialog(),
  );
  if (!context.mounted || item == null) return;
  final href = platformText(item['href'], '');
  if (href.startsWith('/') && !href.startsWith('//')) {
    platformNavigate(context, href);
  }
}

Future<PlatformMap?> choosePlatformCompany(BuildContext context) =>
    showDialog<PlatformMap>(
      context: context,
      builder: (_) => const _PlatformSearchDialog(companiesOnly: true),
    );

class _PlatformSearchDialog extends ConsumerStatefulWidget {
  const _PlatformSearchDialog({this.companiesOnly = false});
  final bool companiesOnly;
  @override
  ConsumerState<_PlatformSearchDialog> createState() =>
      _PlatformSearchDialogState();
}

class _PlatformSearchDialogState extends ConsumerState<_PlatformSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _pending = false;
  int _page = 1;
  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String text, {bool immediate = false}) {
    _debounce?.cancel();
    setState(() => _pending = true);
    void apply() {
      if (mounted) {
        setState(() {
          _query = text.trim();
          _page = 1;
          _pending = false;
        });
      }
    }

    if (immediate) {
      apply();
    } else {
      _debounce = Timer(const Duration(milliseconds: 300), apply);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resource = platformResource('/admin/search', {
      'q': _query,
      'page': '$_page',
      'pageSize': '20',
    });
    return AlertDialog(
      title: Text(
        widget.companiesOnly ? 'Escolher empresa' : 'Pesquisar no Tatuzin',
      ),
      content: SizedBox(
        width: 640,
        height: math.min(520, MediaQuery.sizeOf(context).height * .65),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _search,
              onSubmitted: (text) => _search(text, immediate: true),
              decoration: const InputDecoration(
                labelText: 'Nome, identificação ou e-mail',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _pending
                  ? const Center(child: CircularProgressIndicator())
                  : _query.length < 2
                  ? const PlatformState(
                      message:
                          'Digite pelo menos dois caracteres para pesquisar.',
                    )
                  : PlatformResourceView(
                      resource: resource,
                      builder: (data) {
                        final groups = platformItems(data['groups'])
                            .where(
                              (group) =>
                                  !widget.companiesOnly ||
                                  group['type'] == 'company',
                            )
                            .toList();
                        final hasItems = groups.any(
                          (group) => platformItems(group['items']).isNotEmpty,
                        );
                        if (!hasItems) {
                          return const PlatformState(
                            message:
                                'Nenhum resultado no seu escopo de acesso.',
                          );
                        }
                        return ListView(
                          children: [
                            for (final group in groups) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  group['type'] == 'company'
                                      ? 'Empresas'
                                      : 'Pessoas e acessos',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              for (final item in platformItems(group['items']))
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(platformText(item['label'])),
                                  subtitle: Text(
                                    platformText(item['subtitle'], ''),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.of(context).pop(item),
                                ),
                            ],
                            PlatformPager(
                              page: _page,
                              total: platformInt(data['total']),
                              pageSize: 20,
                              onPage: (page) => setState(() => _page = page),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
