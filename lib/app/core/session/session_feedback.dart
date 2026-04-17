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
  if (normalized.contains('session_revoked') ||
      normalized.contains('sessao revogada') ||
      normalized.contains('sessao foi encerrada')) {
    return 'Sua sessao foi encerrada e precisa ser iniciada novamente.';
  }

  if (normalized.contains('session_expired') ||
      normalized.contains('refresh token expired') ||
      normalized.contains('jwt expired') ||
      normalized.contains('sessao expirada')) {
    return 'Sua sessao expirou. Entre novamente para continuar usando a nuvem.';
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
    return 'Nao foi possivel falar com a nuvem agora. Tente novamente quando a internet estiver estavel.';
  }

  return sanitized;
}
