import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import 'system_support_widgets.dart';

class SystemMockAuthSection extends StatelessWidget {
  const SystemMockAuthSection({
    required this.authState,
    required this.authStatus,
    required this.onMockSignIn,
    required this.onSignOut,
    super.key,
  });

  final AsyncValue<void> authState;
  final AuthStatusSnapshot authStatus;
  final VoidCallback onMockSignIn;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Autenticacao mock',
      subtitle:
          'Ferramenta de diagnostico preservada para testar contexto remoto sem depender do backend real.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemStateTile(
            icon: authStatus.isMockAuthenticated
                ? Icons.badge_outlined
                : Icons.science_outlined,
            title: authStatus.isMockAuthenticated
                ? 'Sessao mock ativa'
                : 'Sessao mock disponivel',
            subtitle: authStatus.isMockAuthenticated
                ? 'A identidade mock continua util para testar a arquitetura hibrida quando voce nao quiser subir a API real.'
                : 'O fluxo mock continua coexistindo com o login real para validar a arquitetura sem bloquear a operacao local.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: authState.isLoading || authStatus.isAuthenticated
                    ? null
                    : onMockSignIn,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Entrar com mock'),
              ),
              OutlinedButton.icon(
                onPressed: authState.isLoading || !authStatus.isMockAuthenticated
                    ? null
                    : onSignOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Encerrar mock'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
