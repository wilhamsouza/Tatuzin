import 'package:flutter/material.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/session/app_session.dart';
import '../../../../app/core/session/auth_provider.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/core/widgets/app_status_badge.dart';
import 'system_support_widgets.dart';

class SystemSessionSection extends StatelessWidget {
  const SystemSessionSection({
    required this.session,
    required this.authStatus,
    super.key,
  });

  final AppSession session;
  final AuthStatusSnapshot authStatus;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Sessao e tenant ativos',
      subtitle:
          'Contexto operacional centralizado para conviver com sessao local, mock e remota real.',
      trailing: AppStatusBadge(
        label: authStatus.sessionLabel,
        tone: authStatus.isRemoteAuthenticated
            ? AppStatusTone.success
            : authStatus.isMockAuthenticated
            ? AppStatusTone.info
            : AppStatusTone.warning,
        icon: authStatus.isRemoteAuthenticated
            ? Icons.verified_user_outlined
            : authStatus.isMockAuthenticated
            ? Icons.science_outlined
            : Icons.offline_bolt_rounded,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SystemInfoRow(label: 'Usuario', value: authStatus.userLabel),
          SystemInfoRow(label: 'Perfil', value: session.user.roleLabel),
          SystemInfoRow(
            label: 'E-mail ativo',
            value: authStatus.email ?? 'Nao autenticado',
          ),
          SystemInfoRow(
            label: 'Empresa ativa',
            value: authStatus.companyLabel,
          ),
          SystemInfoRow(
            label: 'Plano cloud',
            value: authStatus.licensePlanLabel,
          ),
          SystemInfoRow(
            label: 'Status da licenca',
            value: authStatus.licenseStatusLabel,
          ),
          SystemInfoRow(
            label: 'Cloud/sync',
            value: authStatus.cloudSyncLabel,
          ),
          SystemInfoRow(
            label: 'Validade',
            value: authStatus.licenseExpiresAt == null
                ? 'Sem vencimento'
                : AppFormatters.shortDate(authStatus.licenseExpiresAt!),
          ),
          SystemInfoRow(
            label: 'Tenant remoto',
            value: session.company.hasRemoteIdentity
                ? session.company.remoteId!
                : 'Nao vinculado',
          ),
          SystemInfoRow(
            label: 'Inicio da sessao',
            value: AppFormatters.shortDateTime(session.startedAt),
          ),
        ],
      ),
    );
  }
}
