import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin_web nao expoe execucao real de support-actions na UI', () {
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
}
