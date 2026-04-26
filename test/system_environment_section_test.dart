import 'package:erp_pdv_app/app/core/config/app_environment.dart';
import 'package:erp_pdv_app/app/core/network/endpoint_config.dart';
import 'package:erp_pdv_app/app/core/session/session_provider.dart';
import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/system/presentation/widgets/system_environment_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const guard = SessionGuardSnapshot(
    allowOperationalRoutes: true,
    allowRemoteRoutes: true,
    requiresAuthenticationBeforeRemote: false,
  );

  AppEnvironment buildOfficialEnvironment() {
    return AppEnvironment.remoteDefault().copyWith(
      endpointConfig: const EndpointConfig(
        baseUrl: EndpointConfig.productionBaseUrl,
        apiVersion: EndpointConfig.defaultApiVersion,
      ),
    );
  }

  Future<void> pumpSection(
    WidgetTester tester, {
    required AppEnvironment environment,
    required bool canEditEndpoint,
    TextEditingController? endpointController,
    FocusNode? endpointFocusNode,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SystemEnvironmentSection(
              environment: environment,
              guard: guard,
              canEditEndpoint: canEditEndpoint,
              endpointController: endpointController,
              endpointFocusNode: endpointFocusNode,
              onDataModeChanged: (_) {},
              onSaveEndpoint: () {},
              onUseDefaultEndpoint: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('nao mostra edicao de endpoint para usuario comum', (
    tester,
  ) async {
    await pumpSection(
      tester,
      environment: buildOfficialEnvironment(),
      canEditEndpoint: false,
    );

    expect(find.text('Override tecnico de endpoint (debug)'), findsNothing);
    expect(find.text('Salvar endpoint tecnico'), findsNothing);
    expect(find.text('Usar endpoint tecnico padrao'), findsNothing);
    expect(find.text('API oficial'), findsOneWidget);
    expect(find.text(EndpointConfig.productionApiUrl), findsAtLeastNWidgets(1));
  });

  testWidgets(
    'mantem override tecnico visivel apenas quando o modo interno libera',
    (tester) async {
      final controller = TextEditingController(
        text: EndpointConfig.localDevelopmentBaseUrl,
      );
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await pumpSection(
        tester,
        environment: buildOfficialEnvironment(),
        canEditEndpoint: true,
        endpointController: controller,
        endpointFocusNode: focusNode,
      );

      expect(find.text('Override tecnico de endpoint (debug)'), findsOneWidget);
      expect(find.text('Salvar endpoint tecnico'), findsOneWidget);
      expect(find.text('Usar endpoint tecnico padrao'), findsOneWidget);
      expect(find.text('Base URL tecnica do backend'), findsOneWidget);
    },
  );
}
