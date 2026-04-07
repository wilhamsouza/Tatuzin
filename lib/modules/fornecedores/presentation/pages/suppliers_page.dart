import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/providers/app_data_refresh_provider.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/supplier.dart';
import '../providers/supplier_providers.dart';
import '../widgets/supplier_card.dart';

class SuppliersPage extends ConsumerWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(supplierListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fornecedores')),
      drawer: const AppMainDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.pushNamed(AppRouteNames.supplierForm);
          if (created == true) {
            ref.invalidate(supplierListProvider);
          }
        },
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Novo fornecedor'),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: AppPageHeader(
              title: 'Fornecedores',
              subtitle:
                  'Centralize contatos, pend\u00eancias e relacionamento com quem abastece a opera\u00e7\u00e3o.',
              badgeLabel: 'Parceiros',
              badgeIcon: Icons.local_shipping_outlined,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: AppInput(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar por nome, documento ou telefone',
              onChanged: (value) {
                ref.read(supplierSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          Expanded(
            child: suppliersAsync.when(
              data: (suppliers) {
                if (suppliers.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum fornecedor cadastrado ainda.'),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(supplierListProvider);
                    await ref.read(supplierListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: suppliers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final supplier = suppliers[index];
                      return SupplierCard(
                        supplier: supplier,
                        onTap: () => context.pushNamed(
                          AppRouteNames.supplierDetail,
                          pathParameters: {'supplierId': '${supplier.id}'},
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () async {
                                final updated = await context.pushNamed(
                                  AppRouteNames.supplierForm,
                                  extra: supplier,
                                );
                                if (updated == true) {
                                  ref.invalidate(supplierListProvider);
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Excluir',
                              onPressed: () => _delete(context, ref, supplier),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Falha ao carregar fornecedores: $error'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Supplier supplier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir fornecedor'),
          content: Text('Deseja excluir "${supplier.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(supplierRepositoryProvider).delete(supplier.id);
      ref.read(appDataRefreshProvider.notifier).state++;
      ref.invalidate(supplierListProvider);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fornecedor "${supplier.name}" exclu\u00eddo.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'N\u00e3o foi poss\u00edvel excluir o fornecedor: $error',
          ),
        ),
      );
    }
  }
}
