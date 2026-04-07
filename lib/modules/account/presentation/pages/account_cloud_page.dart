import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/session/session_feedback.dart';
import '../../../../app/core/session/session_provider.dart';
import '../../../../app/core/widgets/app_button.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import '../../../../app/routes/route_names.dart';
import '../providers/account_cloud_providers.dart';

class AccountCloudPage extends ConsumerWidget {
  const AccountCloudPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authState = ref.watch(authControllerProvider);
    final authStatus = ref.watch(authStatusProvider);
    final company = ref.watch(currentCompanyContextProvider);
    final accountCloud = ref.watch(accountCloudStatusProvider);
    final internalAccess = ref.watch(internalMobileSurfaceAccessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Conta e nuvem')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          AppPageHeader(
            title: 'Conta e nuvem',
            subtitle:
                'Veja sua conta, sua empresa e como a nuvem esta ajudando o seu negocio sem entrar em detalhes tecnicos.',
            badgeLabel: accountCloud.statusLabel,
            badgeIcon: accountCloud.icon,
            emphasized: true,
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Sua conta',
            subtitle:
                'Informacoes simples sobre quem esta usando o app neste aparelho.',
            child: Column(
              children: [
                _InfoRow(label: 'Usuario', value: authStatus.userLabel),
                if (authStatus.email?.trim().isNotEmpty ?? false)
                  _InfoRow(label: 'E-mail', value: authStatus.email!.trim()),
                _InfoRow(label: 'Sessao', value: accountCloud.accountModeLabel),
                const _InfoRow(
                  label: 'Acesso local',
                  value: 'Sempre disponivel neste aparelho',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Sua empresa',
            subtitle:
                'Resumo comercial da empresa conectada a esta instalacao do Tatuzin.',
            child: Column(
              children: [
                _InfoRow(label: 'Empresa', value: authStatus.companyLabel),
                _InfoRow(label: 'Plano', value: authStatus.licensePlanLabel),
                _InfoRow(
                  label: 'Licenca',
                  value: authStatus.licenseStatusLabel,
                ),
                _InfoRow(
                  label: 'Validade',
                  value: authStatus.licenseExpiresAt == null
                      ? 'Nao informada'
                      : AppFormatters.shortDate(authStatus.licenseExpiresAt!),
                ),
                _InfoRow(
                  label: 'Uso na nuvem',
                  value: company.allowsCloudSync
                      ? 'Disponivel'
                      : 'Uso local disponivel',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Nuvem',
            subtitle:
                'Um status claro para voce saber se a conta esta conectada e se a nuvem esta acompanhando sua empresa.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusBadge(
                      label: accountCloud.statusLabel,
                      tone: accountCloud.tone,
                      icon: accountCloud.icon,
                    ),
                    AppStatusBadge(
                      label: accountCloud.accountModeLabel,
                      tone: authStatus.isRemoteAuthenticated
                          ? AppStatusTone.info
                          : AppStatusTone.neutral,
                      icon: authStatus.isRemoteAuthenticated
                          ? Icons.verified_user_rounded
                          : Icons.offline_bolt_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  accountCloud.statusMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  label: 'Status da nuvem',
                  value: accountCloud.cloudAvailabilityLabel,
                ),
                if (accountCloud.supportingValue != null)
                  _InfoRow(
                    label: accountCloud.supportingLabel ?? 'Atualizacao',
                    value: accountCloud.supportingValue!,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Sessao',
            subtitle:
                'Entre, saia ou recupere sua conta quando quiser usar a nuvem sem perder o modo local.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!authStatus.isRemoteAuthenticated &&
                    authStatus.canAttemptRemoteLogin) ...[
                  AppButton.primary(
                    label: authState.isLoading
                        ? 'Abrindo sua conta...'
                        : 'Entrar com conta',
                    icon: Icons.login_rounded,
                    onPressed: authState.isLoading
                        ? null
                        : () => context.goNamed(AppRouteNames.login),
                    expand: true,
                  ),
                  const SizedBox(height: 12),
                  AppButton.secondary(
                    label: 'Restaurar sessao',
                    icon: Icons.refresh_rounded,
                    onPressed: authState.isLoading
                        ? null
                        : () => _restoreSession(context, ref),
                    expand: true,
                  ),
                ] else if (authStatus.isRemoteAuthenticated) ...[
                  AppButton.primary(
                    label: authState.isLoading
                        ? 'Saindo da conta...'
                        : 'Sair da conta',
                    icon: Icons.logout_rounded,
                    onPressed: authState.isLoading
                        ? null
                        : () => _signOutToLocalMode(context, ref),
                    expand: true,
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  authStatus.canAttemptRemoteLogin
                      ? authStatus.isRemoteAuthenticated
                            ? 'Ao sair da conta, o Tatuzin continua disponivel em modo local neste dispositivo.'
                            : 'Mesmo sem entrar na conta, voce pode continuar vendendo e usando o app no modo local.'
                      : 'A nuvem nao esta disponivel neste momento. Seu uso local continua liberado normalmente.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppSectionCard(
            title: 'Ajuda e suporte',
            subtitle:
                'Quando a nuvem precisa de atencao, sua operacao local continua disponivel neste aparelho.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se voce precisar renovar o acesso, basta entrar novamente na sua conta. Em caso de internet instavel, o Tatuzin continua funcionando localmente.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (authStatus.isPlatformAdmin &&
                    internalAccess.canOpenTechnicalSystem) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Acesso interno',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      AppButton.secondary(
                        label: 'Ferramentas internas',
                        icon: Icons.build_circle_outlined,
                        compact: true,
                        onPressed: () =>
                            context.goNamed(AppRouteNames.technicalSystem),
                      ),
                      if (internalAccess.canOpenAdminCloud)
                        AppButton.secondary(
                          label: 'Painel cloud interno',
                          icon: Icons.admin_panel_settings_outlined,
                          compact: true,
                          onPressed: () => context.goNamed(AppRouteNames.admin),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreSession(BuildContext context, WidgetRef ref) async {
    try {
      final session = await ref
          .read(authControllerProvider.notifier)
          .restoreRemoteSession();
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      if (session == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Nao encontramos uma sessao salva neste aparelho.'),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Sessao restaurada com sucesso.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _signOutToLocalMode(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authControllerProvider.notifier).signOutCurrentSession();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voce saiu da conta. O Tatuzin continua no modo local.',
          ),
        ),
      );
      context.goNamed(AppRouteNames.accountCloud);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlySessionFeedbackMessage(
              error,
              fallback: 'Nao foi possivel sair da conta agora.',
            ),
          ),
        ),
      );
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
