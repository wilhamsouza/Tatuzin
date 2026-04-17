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

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _companySlugController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _userNameController.dispose();
    _companyNameController.dispose();
    _companySlugController.dispose();
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
              AppTheme.primary.withValues(alpha: 0.1),
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
              constraints: const BoxConstraints(maxWidth: 560),
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
                            'Criar conta na nuvem',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Cadastre sua empresa e seu usuario owner para entrar no fluxo cloud do Tatuzin.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 18),
                          AppInput(
                            controller: _userNameController,
                            labelText: 'Nome do responsavel',
                            hintText: 'Seu nome',
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            enabled: !isBusy,
                            prefixIcon: const Icon(
                              Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AppInput(
                            controller: _companyNameController,
                            labelText: 'Nome da empresa',
                            hintText: 'Minha Loja',
                            textInputAction: TextInputAction.next,
                            enabled: !isBusy,
                            prefixIcon: const Icon(Icons.storefront_outlined),
                          ),
                          const SizedBox(height: 12),
                          AppInput(
                            controller: _companySlugController,
                            labelText: 'Slug da empresa',
                            hintText: 'minha-loja',
                            textInputAction: TextInputAction.next,
                            enabled: !isBusy,
                            prefixIcon: const Icon(Icons.tag_rounded),
                            onChanged: (value) {
                              final normalized = _normalizeSlug(value);
                              if (normalized == value) {
                                return;
                              }
                              _companySlugController.value = TextEditingValue(
                                text: normalized,
                                selection: TextSelection.collapsed(
                                  offset: normalized.length,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Use apenas letras minusculas, numeros e hifens.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
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
                            hintText:
                                'Crie uma senha com pelo menos 8 caracteres',
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
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
                            onSubmitted: (_) => canAttemptRemoteLogin && !isBusy
                                ? _handleRegister(context)
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
                                friendlySessionFeedbackMessage(
                                  authState.error,
                                  fallback:
                                      'Nao foi possivel concluir o cadastro agora.',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          AppButton.primary(
                            label: isBusy ? 'Criando conta...' : 'Criar conta',
                            icon: Icons.app_registration_rounded,
                            onPressed: canAttemptRemoteLogin && !isBusy
                                ? () => _handleRegister(context)
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleRegister(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final userName = _userNameController.text.trim();
    final companyName = _companyNameController.text.trim();
    final companySlug = _normalizeSlug(_companySlugController.text);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (userName.isEmpty ||
        companyName.isEmpty ||
        companySlug.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha os dados da empresa e do responsavel para continuar.',
          ),
        ),
      );
      return;
    }

    if (userName.length < 3 || companyName.length < 3) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Informe pelo menos 3 caracteres no nome do responsavel e da empresa.',
          ),
        ),
      );
      return;
    }

    if (!_isValidEmail(email)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Informe um e-mail valido para continuar.'),
        ),
      );
      return;
    }

    if (companySlug.length < 3) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'O slug da empresa precisa ter pelo menos 3 caracteres.',
          ),
        ),
      );
      return;
    }

    if (!_isValidSlug(companySlug)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Use um slug com letras minusculas, numeros e hifens.'),
        ),
      );
      return;
    }

    if (password.length < 8) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A senha precisa ter pelo menos 8 caracteres.'),
        ),
      );
      return;
    }

    try {
      await ref
          .read(authControllerProvider.notifier)
          .signUpRemote(
            companyName: companyName,
            companySlug: companySlug,
            userName: userName,
            email: email,
            password: password,
          );
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
              fallback: 'Nao foi possivel concluir o cadastro agora.',
            ),
          ),
        ),
      );
    }
  }

  String _normalizeSlug(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]+'), '-');
  }

  bool _isValidSlug(String value) {
    return RegExp(r'^[a-z0-9-]+$').hasMatch(value);
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }
}
