String friendlySessionFeedbackMessage(
  Object? error, {
  String fallback = 'Nao foi possivel concluir esta acao agora.',
}) {
  final raw = error?.toString().replaceFirst('Exception: ', '').trim();
  if (raw == null || raw.isEmpty) {
    return fallback;
  }

  final normalized = raw.toLowerCase();
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

  return raw;
}
