import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_feedback.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/core/widgets/tatuzin_brand.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/theme/app_theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authState = ref.watch(authControllerProvider);
    final authStatus = ref.watch(authStatusProvider);
    final isBusy = authState.isLoading;
    final canAttemptRemoteLogin = authStatus.canAttemptRemoteLogin;

    if (authStatus.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        this.context.goNamed(AppRouteNames.dashboard);
      });
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primary.withValues(alpha: 0.08),
              colorScheme.surface,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                children: [
                  const TatuzinBrandLockup(),
                  const SizedBox(height: 18),
                  AppCard(
                    padding: const EdgeInsets.all(22),
                    borderRadius: 24,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Acesse sua conta',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            canAttemptRemoteLogin
                                ? 'Entre para conectar sua empresa na nuvem ou siga operando normalmente no modo local.'
                                : 'Voce pode seguir no modo local e conectar a conta quando a nuvem estiver disponivel.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppStatusBadge(
                                label: authStatus.isAuthenticated
                                    ? 'Conta conectada'
                                    : 'Modo local',
                                tone: authStatus.isAuthenticated
                                    ? AppStatusTone.success
                                    : AppStatusTone.neutral,
                                icon: authStatus.isAuthenticated
                                    ? Icons.verified_user_rounded
                                    : Icons.offline_bolt_rounded,
                              ),
                              AppStatusBadge(
                                label: canAttemptRemoteLogin
                                    ? 'Nuvem disponivel'
                                    : 'Uso local',
                                tone: canAttemptRemoteLogin
                                    ? AppStatusTone.info
                                    : AppStatusTone.neutral,
                                icon: canAttemptRemoteLogin
                                    ? Icons.cloud_done_rounded
                                    : Icons.storage_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          AppInput(
                            controller: _emailController,
                            labelText: 'E-mail',
                            hintText: 'voce@empresa.com',
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            enabled: !isBusy,
                            prefixIcon: const Icon(
                              Icons.alternate_email_rounded,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AppInput(
                            controller: _passwordController,
                            labelText: 'Senha',
                            hintText: 'Sua senha de acesso',
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            enabled: !isBusy,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: isBusy
                                  ? null
                                  : () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                            ),
                            onSubmitted: (_) => canAttemptRemoteLogin && !isBusy
                                ? _handleRemoteSignIn(context)
                                : null,
                          ),
                          if (authState.hasError) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                _errorMessage(authState.error),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          AppButton.primary(
                            label: isBusy ? 'Entrando...' : 'Entrar',
                            icon: Icons.login_rounded,
                            onPressed: canAttemptRemoteLogin && !isBusy
                                ? () => _handleRemoteSignIn(context)
                                : null,
                            expand: true,
                          ),
                          const SizedBox(height: 12),
                          AppButton.secondary(
                            label: 'Continuar offline',
                            icon: Icons.offline_bolt_rounded,
                            onPressed: isBusy
                                ? null
                                : () => _continueOffline(context),
                            expand: true,
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: canAttemptRemoteLogin && !isBusy
                                  ? () => _handleRestoreSession(context)
                                  : null,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Restaurar sessao'),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: canAttemptRemoteLogin && !isBusy
                                  ? () =>
                                        context.goNamed(AppRouteNames.register)
                                  : null,
                              icon: const Icon(Icons.app_registration_rounded),
                              label: const Text('Criar conta'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    borderRadius: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const TatuzinMascotBadge(size: 52),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Seu negocio continua com voce',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'O Tatuzin foi pensado para apoiar o pequeno negocio com operacao simples e confiavel.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Mesmo sem entrar na nuvem, o app continua pronto para vendas, caixa, compras e operacao offline-first.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            AppStatusBadge(
                              label: 'Vendas locais',
                              tone: AppStatusTone.info,
                              icon: Icons.point_of_sale_rounded,
                            ),
                            AppStatusBadge(
                              label: 'Caixa local',
                              tone: AppStatusTone.success,
                              icon: Icons.account_balance_wallet_rounded,
                            ),
                            AppStatusBadge(
                              label: 'Uso offline',
                              tone: AppStatusTone.neutral,
                              icon: Icons.storage_rounded,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleRemoteSignIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Informe e-mail e senha para entrar.')),
      );
      return;
    }

    try {
      await ref
          .read(authControllerProvider.notifier)
          .signInRemote(email: email, password: password);
      if (!mounted) {
        return;
      }
      this.context.goNamed(AppRouteNames.dashboard);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            friendlySessionFeedbackMessage(
              error,
              fallback: 'Nao foi possivel concluir o acesso agora.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _handleRestoreSession(BuildContext context) async {
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .restoreRemoteSession();
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(this.context);
      if (session == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Nao existe sessao remota salva neste dispositivo.'),
          ),
        );
        return;
      }
      this.context.goNamed(AppRouteNames.dashboard);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            friendlySessionFeedbackMessage(
              error,
              fallback: 'Nao foi possivel restaurar sua sessao agora.',
            ),
          ),
        ),
      );
    }
  }

  void _continueOffline(BuildContext context) {
    ref.read(appSessionProvider.notifier).restoreLocalSession();
    context.goNamed(AppRouteNames.dashboard);
  }

  String _errorMessage(Object? error) {
    return friendlySessionFeedbackMessage(
      error,
      fallback: 'Nao foi possivel concluir o acesso agora.',
    );
  }
}
