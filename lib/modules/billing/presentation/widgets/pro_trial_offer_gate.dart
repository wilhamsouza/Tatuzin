import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/core/entitlements/plan_entitlements.dart';
import '../../../../app/core/session/session_provider.dart';
import '../providers/billing_providers.dart';

const proTrialOfferFriendlyError =
    'Nao foi possivel iniciar a assinatura agora. Tente novamente em alguns minutos.';

class ProTrialOfferGate extends ConsumerStatefulWidget {
  const ProTrialOfferGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ProTrialOfferGate> createState() => _ProTrialOfferGateState();
}

class _ProTrialOfferGateState extends ConsumerState<ProTrialOfferGate> {
  bool _dialogVisible = false;
  bool _offerCheckedForSession = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(billingStatusProvider, (_, __) => _scheduleOfferCheck());
    _scheduleOfferCheck();
    return widget.child;
  }

  void _scheduleOfferCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowOffer());
    });
  }

  Future<void> _maybeShowOffer() async {
    if (!mounted || _dialogVisible || _offerCheckedForSession) {
      return;
    }
    final session = ref.read(appSessionProvider);
    if (!session.isRemoteAuthenticated ||
        !session.isCompanyOwner ||
        session.company.remoteId == null) {
      return;
    }

    final status = ref.read(billingStatusProvider).valueOrNull;
    if (status == null ||
        status.plan != PlanKey.free ||
        status.pendingPlan != null ||
        status.hasProviderSubscription) {
      return;
    }

    _offerCheckedForSession = true;
    final storage = ProTrialOfferStorage();
    final shouldShow = await storage.shouldShow(session.company.remoteId!);
    if (!mounted || !shouldShow) {
      return;
    }

    _dialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProTrialOfferDialog(),
    );
    _dialogVisible = false;
  }
}

class ProTrialOfferStorage {
  static const _prefix = 'billing.pro_trial_offer.defer_until.';
  static const deferDuration = Duration(days: 3);

  Future<bool> shouldShow(String companyId, {DateTime? now}) async {
    final preferences = await SharedPreferences.getInstance();
    final rawValue = preferences.getString('$_prefix$companyId');
    final deferUntil = rawValue == null ? null : DateTime.tryParse(rawValue);
    final currentTime = now ?? DateTime.now();
    return deferUntil == null || !deferUntil.isAfter(currentTime);
  }

  Future<void> defer(String companyId, {DateTime? now}) async {
    final preferences = await SharedPreferences.getInstance();
    final currentTime = now ?? DateTime.now();
    await preferences.setString(
      '$_prefix$companyId',
      currentTime.add(deferDuration).toIso8601String(),
    );
  }
}

class _ProTrialOfferDialog extends ConsumerStatefulWidget {
  const _ProTrialOfferDialog();

  @override
  ConsumerState<_ProTrialOfferDialog> createState() =>
      _ProTrialOfferDialogState();
}

class _ProTrialOfferDialogState extends ConsumerState<_ProTrialOfferDialog> {
  bool _isStarting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Teste gratis o PRO por 15 dias'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Venda mais, controle sua equipe e acompanhe tudo com relatorios avancados.',
              ),
              const SizedBox(height: 16),
              for (final benefit in _benefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(benefit)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Cadastre seu cartao com seguranca pelo Mercado Pago. Voce pode cancelar quando quiser. Se nao cancelar ate o fim do teste, sua assinatura PRO sera renovada automaticamente.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isStarting ? null : _defer,
          child: const Text('Agora nao'),
        ),
        FilledButton(
          onPressed: _isStarting ? null : _activate,
          child: _isStarting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Ativar teste gratis'),
        ),
      ],
    );
  }

  Future<void> _defer() async {
    final companyId = ref.read(appSessionProvider).company.remoteId;
    if (companyId != null) {
      await ProTrialOfferStorage().defer(companyId);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _activate() async {
    setState(() => _isStarting = true);
    try {
      final result = await ref
          .read(billingControllerProvider.notifier)
          .subscribe(PlanKey.pro);
      final checkoutUrl = result.checkoutUrl;
      if (checkoutUrl != null && checkoutUrl.trim().isNotEmpty) {
        await ref.read(checkoutLauncherProvider).openExternal(checkoutUrl);
      }
      ref.invalidate(billingStatusProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(proTrialOfferFriendlyError)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }
}

const _benefits = <String>[
  'Funcionarios com permissoes por cargo',
  'Comissoes de vendedores',
  'Relatorios avancados da loja',
  'Multi-dispositivo',
  'Painel web do dono',
  'Controle de equipe e atividade',
  'Nuvem e sincronizacao',
  'Gestao mais completa para crescer',
];
