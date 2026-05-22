import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../session/session_provider.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/app_main_drawer.dart';
import '../widgets/app_state_card.dart';
import '../../routes/route_names.dart';
import 'plan_entitlements.dart';

class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.locked,
    this.title,
    this.message,
  });

  final FeatureKey feature;
  final Widget child;
  final Widget? locked;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    if (session.hasFeature(feature)) {
      return child;
    }

    return locked ??
        LockedFeaturePage(feature: feature, title: title, message: message);
  }
}

class LockedFeatureCard extends StatelessWidget {
  const LockedFeatureCard({
    super.key,
    required this.feature,
    this.title,
    this.message,
  });

  final FeatureKey feature;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final layout = context.appLayout;
    final requiredPlan = PlanEntitlements.requiredPlanForFeature(feature);
    final defaultMessage = requiredPlan == null
        ? 'Este recurso não está disponível no seu plano atual.'
        : 'Este recurso está disponível no plano ${_planLabel(requiredPlan)}.';

    return Card(
      elevation: 0,
      color: colors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(layout.radiusMd),
        side: BorderSide(color: colors.outlineSoft),
      ),
      child: Padding(
        padding: EdgeInsets.all(layout.space7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              color: theme.colorScheme.primary,
              size: layout.iconLg,
            ),
            SizedBox(height: layout.space5),
            Text(
              title ?? 'Recurso bloqueado',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: layout.space3),
            Text(
              message ?? defaultMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: layout.space6),
            const UpgradePrompt(),
          ],
        ),
      ),
    );
  }
}

class LockedFeaturePage extends StatelessWidget {
  const LockedFeaturePage({
    super.key,
    required this.feature,
    this.title,
    this.message,
  });

  final FeatureKey feature;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Scaffold(
      appBar: AppBar(title: Text(title ?? 'Recurso bloqueado')),
      drawer: const AppMainDrawer(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: EdgeInsets.all(layout.space8),
              child: LockedFeatureCard(
                feature: feature,
                title: title,
                message: message,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PermissionDeniedPage extends StatelessWidget {
  const PermissionDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Scaffold(
      appBar: AppBar(title: const Text('Sem permissão')),
      drawer: const AppMainDrawer(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: EdgeInsets.all(layout.space8),
              child: const AppStateCard(
                title: 'Sem permissão',
                message: 'Você não tem permissão para acessar esta área.',
                icon: Icons.lock_outline_rounded,
                tone: AppStateTone.warning,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UpgradePrompt extends ConsumerWidget {
  const UpgradePrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManageSubscription = ref.watch(appSessionProvider).isCompanyOwner;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!canManageSubscription) ...[
          Text(
            'Peça ao dono da empresa para alterar o plano.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (canManageSubscription)
          FilledButton.icon(
            onPressed: () => context.goNamed(AppRouteNames.subscription),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Ativar teste gratis'),
          ),
      ],
    );
  }
}

String _planLabel(PlanKey plan) {
  switch (plan) {
    case PlanKey.free:
      return 'Free';
    case PlanKey.basic:
      return 'Básico';
    case PlanKey.pro:
      return 'Pro';
  }
}
