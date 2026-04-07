import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tatuzin_admin_web/src/features/auth/presentation/login_page.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renderiza a tela de login administrativo', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Tatuzin Admin'), findsOneWidget);
    expect(find.text('Entrar no painel'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
