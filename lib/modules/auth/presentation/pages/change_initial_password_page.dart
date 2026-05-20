import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_feedback.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_card.dart';
import '../../../../app/core/widgets/app_input.dart';
import '../../../../app/core/widgets/tatuzin_brand.dart';
import '../../../../app/routes/route_names.dart';

class ChangeInitialPasswordPage extends ConsumerStatefulWidget {
  const ChangeInitialPasswordPage({super.key});

  @override
  ConsumerState<ChangeInitialPasswordPage> createState() =>
      _ChangeInitialPasswordPageState();
}

class _ChangeInitialPasswordPageState
    extends ConsumerState<ChangeInitialPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authState = ref.watch(authControllerProvider);
    final isBusy = authState.isLoading;

    return Scaffold(
      body: SafeArea(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crie sua nova senha',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Você precisa criar uma nova senha para continuar.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      AppInput(
                        controller: _passwordController,
                        labelText: 'Nova senha',
                        obscureText: _obscurePassword,
                        enabled: !isBusy,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: isBusy
                              ? null
                              : () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppInput(
                        controller: _confirmPasswordController,
                        labelText: 'Confirmar nova senha',
                        obscureText: _obscureConfirmPassword,
                        enabled: !isBusy,
                        prefixIcon: const Icon(Icons.password_rounded),
                        suffixIcon: IconButton(
                          onPressed: isBusy
                              ? null
                              : () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                        onSubmitted: (_) => isBusy ? null : _submit(),
                      ),
                      const SizedBox(height: 18),
                      AppButton.primary(
                        label: isBusy ? 'Salvando...' : 'Continuar',
                        icon: Icons.check_circle_outline_rounded,
                        onPressed: isBusy ? null : _submit,
                        expand: true,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: isBusy ? null : _goBackToLogin,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Voltar para login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final password = _passwordController.text;
    final confirmation = _confirmPasswordController.text;

    if (password.length < 8) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A nova senha precisa ter pelo menos 8 caracteres.'),
        ),
      );
      return;
    }

    if (password != confirmation) {
      messenger.showSnackBar(
        const SnackBar(content: Text('As senhas não conferem.')),
      );
      return;
    }

    try {
      await ref
          .read(authControllerProvider.notifier)
          .changeInitialPasswordRemote(newPassword: password);
      if (!mounted) {
        return;
      }
      context.goNamed(AppRouteNames.dashboard);
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlySessionFeedbackMessage(
              error,
              fallback: 'Não foi possível criar a nova senha agora.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _goBackToLogin() async {
    try {
      await ref
          .read(authControllerProvider.notifier)
          .discardPendingInitialPasswordSession();
    } catch (_) {
      // Mesmo que o backend esteja indisponivel, a sessao temporaria local
      // precisa sair da tela de troca e voltar ao login.
      ref.read(authControllerProvider.notifier).resetStatus();
    }
    if (!mounted) {
      return;
    }
    context.goNamed(AppRouteNames.login);
  }
}
