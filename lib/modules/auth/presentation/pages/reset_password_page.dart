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

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    final initialToken = widget.initialToken?.trim();
    if (initialToken != null && initialToken.isNotEmpty) {
      _tokenController.text = initialToken;
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
              constraints: const BoxConstraints(maxWidth: 540),
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
                          'Redefinir senha',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cole o token recebido e informe sua nova senha para voltar a acessar a nuvem.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        AppInput(
                          controller: _tokenController,
                          labelText: 'Token de recuperacao',
                          hintText: 'Cole o token aqui',
                          textInputAction: TextInputAction.next,
                          enabled: !isBusy,
                          prefixIcon: const Icon(Icons.key_rounded),
                        ),
                        const SizedBox(height: 12),
                        AppInput(
                          controller: _passwordController,
                          labelText: 'Nova senha',
                          hintText: 'Minimo de 8 caracteres',
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
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
                        ),
                        const SizedBox(height: 12),
                        AppInput(
                          controller: _confirmPasswordController,
                          labelText: 'Confirmar nova senha',
                          hintText: 'Repita a nova senha',
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          enabled: !isBusy,
                          prefixIcon: const Icon(Icons.verified_user_outlined),
                          suffixIcon: IconButton(
                            onPressed: isBusy
                                ? null
                                : () {
                                    setState(() {
                                      _obscureConfirmPassword =
                                          !_obscureConfirmPassword;
                                    });
                                  },
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                          onSubmitted: (_) => canAttemptRemoteLogin && !isBusy
                              ? _handleResetPassword(context)
                              : null,
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: 12),
                          Text(
                            'No ambiente local, o token pode vir de um link futuro ou do log de depuracao do backend quando esse modo estiver habilitado.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        AppButton.primary(
                          label: isBusy
                              ? 'Redefinindo senha...'
                              : 'Salvar nova senha',
                          icon: Icons.password_rounded,
                          onPressed: canAttemptRemoteLogin && !isBusy
                              ? () => _handleResetPassword(context)
                              : null,
                          expand: true,
                        ),
                        const SizedBox(height: 12),
                        AppButton.secondary(
                          label: 'Voltar para login',
                          icon: Icons.arrow_back_rounded,
                          onPressed: isBusy
                              ? null
                              : () => context.goNamed(AppRouteNames.login),
                          expand: true,
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

  Future<void> _handleResetPassword(BuildContext context) async {
    final token = _tokenController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (token.length < 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um token de recuperacao valido.'),
        ),
      );
      return;
    }

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A nova senha precisa ter pelo menos 8 caracteres.'),
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A confirmacao da senha precisa ser igual a nova senha.',
          ),
        ),
      );
      return;
    }

    try {
      final message = await ref
          .read(authControllerProvider.notifier)
          .resetPasswordRemote(token: token, newPassword: password);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        this.context,
      ).showSnackBar(SnackBar(content: Text(message)));
      this.context.goNamed(AppRouteNames.login);
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
                  'Nao foi possivel redefinir a senha com este token agora.',
            ),
          ),
        ),
      );
    }
  }
}
