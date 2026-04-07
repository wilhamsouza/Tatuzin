import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../../compras/presentation/providers/purchase_providers.dart';
import '../../../compras/presentation/widgets/purchase_card.dart';
import '../../domain/entities/supplier.dart';
import '../providers/supplier_providers.dart';
import '../widgets/supplier_card.dart';

class SupplierDetailPage extends ConsumerWidget {
  const SupplierDetailPage({super.key, required this.supplierId});

  final int supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplierAsync = ref.watch(supplierDetailProvider(supplierId));
    final purchasesAsync = ref.watch(purchasesBySupplierProvider(supplierId));

    return Scaffold(
      appBar: AppBar(title: const Text('Fornecedor')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(supplierDetailProvider(supplierId));
          ref.invalidate(purchasesBySupplierProvider(supplierId));
          await ref.read(supplierDetailProvider(supplierId).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            supplierAsync.when(
              data: (supplier) {
                if (supplier == null) {
                  return const AppSectionCard(
                    title: 'Fornecedor nao encontrado',
                    child: Text('Este cadastro nao esta mais disponivel.'),
                  );
                }

                return Column(
                  children: [
                    SupplierCard(
                      supplier: supplier,
                      trailing: FilledButton.tonalIcon(
                        onPressed: () async {
                          final updated = await context.pushNamed(
                            AppRouteNames.supplierForm,
                            extra: supplier,
                          );
                          if (updated == true) {
                            ref.invalidate(supplierDetailProvider(supplierId));
                            ref.invalidate(
                              purchasesBySupplierProvider(supplierId),
                            );
                          }
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SupplierInfoSection(supplier: supplier),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AppSectionCard(
                title: 'Falha ao carregar fornecedor',
                subtitle: error.toString(),
                child: FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(supplierDetailProvider(supplierId)),
                  child: const Text('Tentar novamente'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            AppSectionCard(
              title: 'Compras do fornecedor',
              subtitle: 'Historico e pendencias vinculadas ao cadastro.',
              trailing: FilledButton.tonalIcon(
                onPressed: () => context.pushNamed(
                  AppRouteNames.purchaseForm,
                  extra: supplierId,
                ),
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('Nova compra'),
              ),
              child: purchasesAsync.when(
                data: (purchases) {
                  if (purchases.isEmpty) {
                    return const Text(
                      'Nenhuma compra registrada para este fornecedor.',
                    );
                  }

                  return Column(
                    children: [
                      for (
                        var index = 0;
                        index < purchases.length;
                        index++
                      ) ...[
                        PurchaseCard(
                          purchase: purchases[index],
                          onTap: () => context.pushNamed(
                            AppRouteNames.purchaseDetail,
                            pathParameters: {
                              'purchaseId': '${purchases[index].id}',
                            },
                          ),
                        ),
                        if (index < purchases.length - 1)
                          const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Text('Falha ao carregar compras do fornecedor: $error'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierInfoSection extends StatelessWidget {
  const _SupplierInfoSection({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Dados do fornecedor',
      subtitle: 'Informacoes operacionais e contato.',
      child: Column(
        children: [
          _InfoLine(label: 'Nome', value: supplier.name),
          if (supplier.tradeName?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(label: 'Nome fantasia', value: supplier.tradeName!),
          ],
          if (supplier.document?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(label: 'Documento', value: supplier.document!),
          ],
          if (supplier.phone?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(label: 'Telefone', value: supplier.phone!),
          ],
          if (supplier.email?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(label: 'E-mail', value: supplier.email!),
          ],
          if (supplier.contactPerson?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(
              label: 'Contato responsavel',
              value: supplier.contactPerson!,
            ),
          ],
          if (supplier.address?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(label: 'Endereco', value: supplier.address!),
          ],
          if (supplier.notes?.trim().isNotEmpty ?? false) ...[
            const Divider(height: 24),
            _InfoLine(label: 'Observacao', value: supplier.notes!),
          ],
          const Divider(height: 24),
          _InfoLine(
            label: 'Atualizado em',
            value: AppFormatters.shortDateTime(supplier.updatedAt),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}
