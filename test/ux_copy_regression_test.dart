import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('textos de UX não carregam mojibake conhecido', () {
    final paths = [
      'lib/modules/caixa/presentation/pages/cash_page.dart',
      'lib/modules/more/presentation/pages/more_page.dart',
      'lib/modules/billing/presentation/pages/subscription_page.dart',
      'lib/app/core/entitlements/feature_gate.dart',
      'lib/app/core/widgets/app_main_drawer.dart',
      'lib/modules/dashboard/presentation/pages/dashboard_page.dart',
      'lib/modules/estoque/presentation/pages/inventory_page.dart',
      'lib/modules/auth/presentation/pages/register_page.dart',
    ];

    const unaccentedSettings =
        'Configura'
        'coes';
    final mojibakeSamples = [
      unaccentedSettings,
      'Sess\u00C3\u00A3o',
      'Opera\u00C3\u00A7\u00C3\u00A3o',
      'movimenta\u00C3\u00A7\u00C3\u00B5es',
      'Hist\u00C3\u00B3rico',
      'diferen\u00C3\u00A7a',
      '\u00C3\u00A7',
      '\u00C3\u00B3',
      '\u00C3\u00B5',
      '\u00C3\u00AA',
      '\u00C3\u00AD',
      '\u00C3\u00A1',
      '\u00C3\u00A0',
      '\u00E2\u20AC\u00A2',
      '\u00C3\u00A2',
      '\uFFFD',
    ];
    final mojibake = RegExp(mojibakeSamples.map(RegExp.escape).join('|'));

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains(mojibake)), reason: path);
    }
  });

  test('copy de assinatura não usa owner na UI', () {
    final paths = [
      'lib/modules/billing/presentation/pages/subscription_page.dart',
      'lib/app/core/entitlements/feature_gate.dart',
      'lib/modules/account/presentation/pages/company_page.dart',
      'lib/modules/account/presentation/pages/settings_page.dart',
      'lib/modules/auth/presentation/pages/register_page.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('Somente owner')), reason: path);
      expect(
        RegExp(
          r'''(?:Text|title|subtitle|label|message|fallback)\s*[:(]\s*(?:const\s*)?['"][^'"]*owner[^'"]*['"]''',
          caseSensitive: false,
        ).hasMatch(source),
        isFalse,
        reason: path,
      );
    }
  });
}
