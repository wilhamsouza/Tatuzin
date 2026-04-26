import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import 'system_support_widgets.dart';

class SystemRemoteAuthSection extends StatelessWidget {
  const SystemRemoteAuthSection({
    required this.authState,
    required this.authStatus,
    required this.emailController,
    required this.passwordController,
    required this.onRemoteSignIn,
    required this.onRestoreRemoteSession,
    required this.onSignOut,
    super.key,
  });

  final AsyncValue<void> authState;
  final AuthStatusSnapshot authStatus;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback onRemoteSignIn;
  final VoidCallback onRestoreRemoteSession;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      title: 'Autenticacao remota real',
      subtitle:
          'Login remoto contra a API oficial do Tatuzin. O app continua operando offline mesmo sem sessao remota.',
      trailing: AppStatusBadge(
        label: authStatus.isRemoteAuthenticated
            ? 'Sessao remota ativa'
            : 'Sem sessao remota',
        tone: authStatus.isRemoteAuthenticated
            ? AppStatusTone.success
            : AppStatusTone.neutral,
        icon: authStatus.isRemoteAuthenticated
            ? Icons.lock_open_rounded
            : Icons.lock_outline_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemStateTile(
            icon: authStatus.isRemoteAuthenticated
                ? Icons.hub_rounded
                : Icons.login_rounded,
            title: authStatus.isRemoteAuthenticated
                ? 'Login remoto validado'
                : 'Use a API oficial para autenticar',
            subtitle: authStatus.isRemoteAuthenticated
                ? 'Sessao remota ativa e tenant resolvido pelo backend. Os modulos operacionais continuam locais nesta fase.'
                : 'Ative um modo com backend e entre com seu usuario remoto. O endpoint oficial ja vem nativo neste build.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: emailController,
            enabled: !authState.isLoading,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            enabled: !authState.isLoading,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Senha',
              prefixIcon: Icon(Icons.password_rounded),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed:
                    authState.isLoading || !authStatus.canAttemptRemoteLogin
                    ? null
                    : onRemoteSignIn,
                icon: const Icon(Icons.login_rounded),
                label: Text(
                  authState.isLoading && !authStatus.isRemoteAuthenticated
                      ? 'Entrando...'
                      : 'Entrar com backend',
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    authState.isLoading || !authStatus.canAttemptRemoteLogin
                    ? null
                    : onRestoreRemoteSession,
                icon: const Icon(Icons.history_toggle_off_rounded),
                label: const Text('Restaurar sessao'),
              ),
              OutlinedButton.icon(
                onPressed: authState.isLoading || !authStatus.isAuthenticated
                    ? null
                    : onSignOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sair da sessao atual'),
              ),
            ],
          ),
          if (authState.hasError) ...[
            const SizedBox(height: 12),
            Text(
              authState.error.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
