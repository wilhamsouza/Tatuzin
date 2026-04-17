import 'package:flutter/foundation.dart' show kDebugMode;
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
import '../../../../app/theme/app_theme.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    ref.read(authControllerProvider.notifier).resetStatus();
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recuperar senha',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Informe seu e-mail para solicitar um token de redefinicao de senha.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        AppInput(
                          controller: _emailController,
                          labelText: 'E-mail',
                          hintText: 'voce@empresa.com',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.username],
                          enabled: !isBusy,
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                          onSubmitted: (_) => canAttemptRemoteLogin && !isBusy
                              ? _handleForgotPassword(context)
                              : null,
                        ),
                        if (_successMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              _successMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                        if (kDebugMode) ...[
                          const SizedBox(height: 12),
                          Text(
                            'No ambiente local, se o backend estiver com recuperacao em modo de teste, o token pode aparecer apenas nos logs do servidor.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        AppButton.primary(
                          label: isBusy
                              ? 'Solicitando token...'
                              : 'Enviar instrucoes',
                          icon: Icons.mark_email_read_outlined,
                          onPressed: canAttemptRemoteLogin && !isBusy
                              ? () => _handleForgotPassword(context)
                              : null,
                          expand: true,
                        ),
                        const SizedBox(height: 12),
                        AppButton.secondary(
                          label: 'Ja tenho um token',
                          icon: Icons.key_rounded,
                          onPressed: isBusy
                              ? null
                              : () => context.goNamed(
                                  AppRouteNames.resetPassword,
                                ),
                          expand: true,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: isBusy
                                ? null
                                : () => context.goNamed(AppRouteNames.login),
                            icon: const Icon(Icons.arrow_back_rounded),
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
      ),
    );
  }

  Future<void> _handleForgotPassword(BuildContext context) async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um e-mail valido para continuar.'),
        ),
      );
      return;
    }

    try {
      final message = await ref
          .read(authControllerProvider.notifier)
          .forgotPasswordRemote(email: email);
      if (!mounted) {
        return;
      }
      setState(() {
        _successMessage = message;
      });
      ScaffoldMessenger.of(
        this.context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            friendlySessionFeedbackMessage(
              error,
              fallback:
                  'Nao foi possivel solicitar a recuperacao de senha agora.',
            ),
          ),
        ),
      );
    }
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }
}
