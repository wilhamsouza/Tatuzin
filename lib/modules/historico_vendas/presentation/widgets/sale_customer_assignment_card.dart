import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/core/app_context/app_operational_context.dart';
import '../../../../app/core/database/app_database.dart';
import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/providers/tenant_bootstrap_gate.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../clientes/domain/entities/client.dart';
import '../../../clientes/presentation/providers/client_providers.dart';
import '../../../comprovantes/presentation/providers/receipt_providers.dart';
import '../../../comprovantes/domain/entities/commercial_receipt_request.dart';
import '../../data/sale_customer_assignment_repository.dart';

final saleCustomerAssignmentRepositoryProvider = Provider(
  (ref) => SaleCustomerAssignmentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(appOperationalContextProvider),
  ),
);

final saleCustomerAssignmentStateProvider =
    FutureProvider.family<({String? restriction, String? sync}), int>((
      ref,
      id,
    ) async {
      ref.watch(appDataRefreshProvider);
      await requireTenantBootstrapReady(
        ref,
        'saleCustomerAssignmentStateProvider',
      );
      final repository = ref.watch(saleCustomerAssignmentRepositoryProvider);
      return (
        restriction: await repository.restriction(id),
        sync: await repository.syncMessage(id),
      );
    });

class SaleCustomerAssignmentCard extends ConsumerStatefulWidget {
  const SaleCustomerAssignmentCard({
    super.key,
    required this.saleId,
    required this.hasClient,
  });
  final int saleId;
  final bool hasClient;
  @override
  ConsumerState<SaleCustomerAssignmentCard> createState() =>
      _AssignmentCardState();
}

class _AssignmentCardState extends ConsumerState<SaleCustomerAssignmentCard> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Cliente da venda',
      child: ref
          .watch(saleCustomerAssignmentStateProvider(widget.saleId))
          .when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => TextButton(
              onPressed: () => ref.invalidate(
                saleCustomerAssignmentStateProvider(widget.saleId),
              ),
              child: const Text('Tentar carregar o vínculo de cliente'),
            ),
            data: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.restriction != null) Text(state.restriction!),
                if (state.sync != null) Text(state.sync!),
                if (state.restriction == null)
                  OutlinedButton.icon(
                    onPressed: _saving || state.sync != null ? null : _pick,
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(
                      _saving
                          ? 'Salvando…'
                          : widget.hasClient
                          ? 'Alterar cliente'
                          : 'Vincular cliente',
                    ),
                  ),
              ],
            ),
          ),
    );
  }

  Future<void> _pick() async {
    final runtime = ref.read(sessionRuntimeKeyProvider);
    final customer = await showModalBottomSheet<Client>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CustomerPicker(),
    );
    if (!mounted ||
        customer == null ||
        runtime != ref.read(sessionRuntimeKeyProvider)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(saleCustomerAssignmentRepositoryProvider)
          .assign(widget.saleId, customer.id);
      if (!mounted || runtime != ref.read(sessionRuntimeKeyProvider)) return;
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(
        commercialReceiptProvider(
          CommercialReceiptRequest.sale(saleId: widget.saleId),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cliente vinculado. Alteração pendente de sincronização.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();
  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar cliente por nome',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: ref
                  .watch(pdvCustomerLookupProvider(_query))
                  .when(
                    data: (clients) => clients.isEmpty
                        ? const Center(
                            child: Text('Nenhum cliente encontrado.'),
                          )
                        : ListView.builder(
                            itemCount: clients.length,
                            itemBuilder: (context, index) => ListTile(
                              title: Text(clients[index].name),
                              onTap: () =>
                                  Navigator.of(context).pop(clients[index]),
                            ),
                          ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => TextButton(
                      onPressed: () =>
                          ref.invalidate(pdvCustomerLookupProvider(_query)),
                      child: const Text('Tentar novamente'),
                    ),
                  ),
            ),
          ],
        ),
      ),
    ),
  );
}
