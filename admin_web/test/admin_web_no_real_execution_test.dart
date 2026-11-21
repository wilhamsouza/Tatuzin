import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI não chama diretamente o executor legado de revogação', () {
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final source = libFiles.map((file) => file.readAsStringSync()).join('\n');

    expect(source, isNot(contains('/support-actions/revoke-session/execute')));
    expect(source, isNot(contains('support-actions/revoke-session/execute')));
    expect(source, isNot(contains('Executar revogacao')));
    expect(source, isNot(contains('Revogar sessao agora')));
    expect(source, isNot(contains('Confirmar execucao')));
    expect(source, isNot(contains('Aplicar acao')));
    expect(source, isNot(contains('Bloquear usuario')));
    expect(source, isNot(contains('Forcar sync')));
    expect(source, isNot(contains('Resolver conflito')));
    expect(source, isNot(contains('Enviar push')));
  });

  test('painel novo mantém operações excepcionais fora dos controles', () {
    final source = Directory('lib/src/features/platform')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    for (final forbidden in [
      '/force-plan',
      '/cancel-local',
      '/reconcile',
      '/resolve-conflict',
      '/send-push',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });
}
