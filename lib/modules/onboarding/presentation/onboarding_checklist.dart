import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/core/session/session_provider.dart';
import '../../../app/core/widgets/app_section_card.dart';
import '../../../app/routes/route_names.dart';
import '../domain/onboarding_progress.dart';
import 'onboarding_providers.dart';

class CompanyOnboardingCard extends ConsumerWidget {
  const CompanyOnboardingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    if (!session.isCompanyOwner) return const SizedBox.shrink();
    return ref
        .watch(companyOnboardingProvider)
        .when(
          data: (progress) {
            if (progress == null || !progress.enabled || progress.completed) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OnboardingChecklist(
                progress: progress,
                onProduct: () => context.pushNamed(AppRouteNames.productForm),
                onCash: () => context.pushNamed(AppRouteNames.cash),
                onSale: () => context.pushNamed(AppRouteNames.sales),
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              title: const Text('Primeiros passos indisponíveis agora'),
              subtitle: const Text('Você pode continuar usando a loja.'),
              trailing: TextButton(
                onPressed: () => ref.invalidate(companyOnboardingProvider),
                child: const Text('Tentar novamente'),
              ),
            ),
          ),
        );
  }
}

class OnboardingChecklist extends StatefulWidget {
  const OnboardingChecklist({
    super.key,
    required this.progress,
    required this.onProduct,
    required this.onCash,
    required this.onSale,
  });
  final OnboardingProgress progress;
  final VoidCallback onProduct;
  final VoidCallback onCash;
  final VoidCallback onSale;

  @override
  State<OnboardingChecklist> createState() => _OnboardingChecklistState();
}

class _OnboardingChecklistState extends State<OnboardingChecklist> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return ListTile(
        leading: const Icon(Icons.checklist_rounded),
        title: const Text('Continuar configuração da loja'),
        subtitle: Text(
          '${widget.progress.completedSteps} de 3 passos concluídos',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => _expanded = true),
      );
    }
    return AppSectionCard(
      title: 'Sua primeira venda começa aqui',
      subtitle: 'Prepare sua loja em três passos. Você pode continuar depois.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: widget.progress.completedSteps / 3,
            semanticsLabel:
                'Configuração da loja: ${widget.progress.completedSteps} de 3 passos',
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              widget.progress.productReady
                  ? Icons.check_circle
                  : Icons.inventory_2_outlined,
            ),
            title: const Text('1. Cadastre seu primeiro produto'),
            subtitle: const Text('Nome, preço, estoque e grade opcional.'),
            onTap: widget.onProduct,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              widget.progress.cashReady
                  ? Icons.check_circle
                  : Icons.account_balance_wallet_outlined,
            ),
            title: const Text('2. Prepare o caixa'),
            subtitle: const Text('Abra ou confirme o caixa para começar.'),
            onTap: widget.onCash,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              widget.progress.completed
                  ? Icons.check_circle
                  : Icons.point_of_sale,
            ),
            title: const Text('3. Faça sua primeira venda'),
            subtitle: const Text('Registre uma venda real para concluir.'),
            onTap: widget.onSale,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _expanded = false),
              child: const Text('Continuar depois'),
            ),
          ),
        ],
      ),
    );
  }
}
