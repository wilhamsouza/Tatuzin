import '../errors/app_exceptions.dart';

String friendlySessionFeedbackMessage(
  Object? error, {
  String fallback = 'Nao foi possivel concluir esta acao agora.',
}) {
  final raw = error?.toString().replaceFirst('Exception: ', '').trim();
  if (raw == null || raw.isEmpty) {
    return fallback;
  }

  final sanitized = raw
      .replaceFirst(RegExp(r'^Falha ao chamar [^:]+:\s*'), '')
      .trim();
  final normalized = sanitized.toLowerCase();
  if (normalized.contains('tenant_pending_deletion') ||
      normalized.contains('processo de exclusao') ||
      normalized.contains('processo de exclusÃ£o')) {
    return tenantPendingDeletionMessage;
  }

  if (normalized.contains('license_expired')) {
    return 'A licença da empresa está expirada. Regularize a assinatura para continuar.';
  }

  if (normalized.contains('invalid_credentials')) {
    return 'E-mail ou senha inválidos.';
  }

  if (normalized.contains('temporary_password_expired')) {
    return 'Essa senha expirou. Peça ao dono para gerar uma nova.';
  }

  if (normalized.contains('initial_password_change_required')) {
    return 'Você precisa criar uma nova senha para continuar.';
  }

  if (normalized.contains('employee_disabled')) {
    return 'Seu acesso foi desativado. Fale com o dono da empresa.';
  }

  if (normalized.contains('auth_required') ||
      normalized.contains('invalid_access_token')) {
    return 'Sua sessão expirou. Entre novamente.';
  }

  if (normalized.contains('session_revoked') ||
      normalized.contains('sessao revogada') ||
      normalized.contains('sessao foi encerrada')) {
    return 'Sua sessao foi encerrada e precisa ser iniciada novamente.';
  }

  if (normalized.contains('session_expired') ||
      normalized.contains('refresh token expired') ||
      normalized.contains('jwt expired') ||
      normalized.contains('sessao expirada')) {
    return 'Sua sessão expirou. Entre novamente.';
  }

  if (normalized.contains('device_limit') ||
      normalized.contains('limite de dispositivos')) {
    return 'Sua licenca atingiu o limite de dispositivos conectados.';
  }

  if (normalized.contains('email_already_in_use') ||
      normalized.contains('ja existe uma conta cadastrada com este e-mail')) {
    return 'Ja existe uma conta cadastrada com este e-mail.';
  }

  if (normalized.contains('company_slug_already_in_use') ||
      normalized.contains('identificador de empresa ja esta em uso')) {
    return 'Este identificador de empresa ja esta em uso.';
  }

  if (normalized.contains('auth_register_rate_limited') ||
      normalized.contains('muitas tentativas de cadastro')) {
    return 'Muitas tentativas de cadastro em pouco tempo. Aguarde um pouco e tente novamente.';
  }

  if (normalized.contains('auth_forgot_password_rate_limited') ||
      normalized.contains('muitas tentativas de recuperacao de senha')) {
    return 'Muitas tentativas de recuperacao de senha em pouco tempo. Aguarde um pouco e tente novamente.';
  }

  if (normalized.contains('auth_reset_password_rate_limited') ||
      normalized.contains('muitas tentativas de redefinicao de senha')) {
    return 'Muitas tentativas de redefinicao de senha em pouco tempo. Aguarde um pouco e tente novamente.';
  }

  if (normalized.contains('password_reset_token_invalid') ||
      normalized.contains('token de redefinicao de senha e invalido')) {
    return 'O token de recuperacao informado nao e valido.';
  }

  if (normalized.contains('password_reset_token_expired') ||
      normalized.contains('token de redefinicao de senha expirou')) {
    return 'O token de recuperacao expirou. Solicite um novo token para continuar.';
  }

  if (normalized.contains('password_reset_token_already_used') ||
      normalized.contains('token de redefinicao de senha ja foi utilizado')) {
    return 'Esse token ja foi usado. Solicite um novo token para redefinir a senha.';
  }

  if (normalized.contains('validation_error') ||
      normalized.contains('dados invalidos enviados para a api')) {
    return 'Revise os dados informados e tente novamente.';
  }

  if (normalized.contains('cloud_sync_disabled') ||
      normalized.contains('nuvem indisponivel') ||
      normalized.contains('cloud disabled')) {
    return 'A nuvem nao esta disponivel para esta empresa no momento.';
  }

  if (normalized.contains('network') ||
      normalized.contains('timeout') ||
      normalized.contains('socket') ||
      normalized.contains('internet') ||
      normalized.contains('conexao')) {
    return 'Não foi possível falar com a nuvem agora. Verifique sua conexão.';
  }

  return sanitized;
}
