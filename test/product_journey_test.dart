import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin/app/core/config/app_environment.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/auth_token_storage.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/app/core/telemetry/journey_queue.dart';
import 'package:tatuzin/app/core/telemetry/product_journey.dart';

AppSession _session(String company, {bool offline = true}) => AppSession(
  scope: SessionScope.authenticatedRemote,
  user: const AppUser(
    localId: null,
    remoteId: 'user',
    displayName: 'Dono',
    email: null,
    roleLabel: 'OWNER',
    kind: AppUserKind.remoteAuthenticated,
  ),
  company: CompanyContext(
    localId: null,
    remoteId: company,
    displayName: company,
    legalName: company,
    documentNumber: null,
  ),
  startedAt: DateTime.now(),
  isOfflineFallback: offline,
  clientInstanceId: 'device',
);

String _scope(String company) =>
    base64Url.encode(utf8.encode(jsonEncode([company, 'device'])));
Map<String, dynamic> _event(String id) => {
  'eventId': id,
  'occurredAt': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'concurrent appends and acknowledgements preserve unsent events and tenant isolation',
    () async {
      final queue = JourneyQueue();
      await Future.wait([
        queue.append('a', _event('1')),
        queue.append('a', _event('2')),
        queue.append('b', _event('1')),
        queue.acknowledge('a', {'1'}),
        queue.append('a', _event('3')),
      ]);
      expect((await queue.batch('a')).map((event) => event['eventId']), [
        '2',
        '3',
      ]);
      expect((await queue.batch('b')).single['eventId'], '1');
    },
  );

  test(
    'retention prunes inactive scopes and leaves unrelated preferences intact',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('session.keep', 'yes');
      await preferences.setString(
        'product_journey.v1.old',
        jsonEncode([
          {
            'eventId': 'old',
            'occurredAt': DateTime.now()
                .subtract(const Duration(days: 91))
                .toUtc()
                .toIso8601String(),
          },
        ]),
      );
      await JourneyQueue().pruneExpired();
      expect(preferences.getString('product_journey.v1.old'), isNull);
      expect(preferences.getString('session.keep'), 'yes');
    },
  );

  test('queue remains bounded and batches are at most fifty events', () async {
    final queue = JourneyQueue();
    for (var i = 0; i < JourneyQueue.maxEvents + 2; i++) {
      await queue.append('a', _event('$i'));
    }
    final batch = await queue.batch('a');
    expect(batch.length, 50);
    expect(batch.first['eventId'], '2');
  });

  test(
    'offline events survive failures, reuse ids and clear only acknowledged events',
    () async {
      var session = _session('a');
      final queue = JourneyQueue();
      var status = 503;
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        expect(request.headers['Authorization'], 'Bearer token');
        final events = body['events'] as List;
        return http.Response(
          jsonEncode({
            'acknowledgedEventIds': [events.first['eventId']],
          }),
          status,
        );
      });
      final service = ProductJourney(
        readSession: () => session,
        readEnvironment: AppEnvironment.remoteDefault,
        tokenStorage: _Tokens(),
        client: client,
        queue: queue,
      );
      addTearDown(service.dispose);
      service.record(JourneyEvent.productCreated);
      service.record(JourneyEvent.cashOpened);
      expect((await queue.batch(_scope('a'))).length, 2);
      expect(requests, isEmpty);
      session = session.copyWith(isOfflineFallback: false);
      await service.flush();
      expect((await queue.batch(_scope('a'))).length, 2);
      status = 200;
      await service.flush();
      expect((await queue.batch(_scope('a'))).length, 1);
      expect(
        (requests.first['events'] as List).first['eventId'],
        (requests.last['events'] as List).first['eventId'],
      );
      session = _session('b', offline: false);
      await service.flush();
      expect(requests.length, 2);
    },
  );

  test(
    'a company change while reading the token cannot send the previous company queue',
    () async {
      var session = _session('a');
      final tokens = _Tokens();
      final queue = JourneyQueue();
      var requests = 0;
      final service = ProductJourney(
        readSession: () => session,
        readEnvironment: AppEnvironment.remoteDefault,
        tokenStorage: tokens,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
        queue: queue,
      );
      addTearDown(service.dispose);
      service.record(JourneyEvent.productCreated);
      await queue.batch(_scope('a'));
      session = session.copyWith(isOfflineFallback: false);
      final tokenRead = Completer<String?>();
      tokens.pending = tokenRead.future;
      final flushing = service.flush();
      await Future<void>.delayed(Duration.zero);
      session = _session('b', offline: false);
      tokenRead.complete('token');
      await flushing;
      expect(requests, 0);
      expect((await queue.batch(_scope('a'))).length, 1);
    },
  );

  test(
    'checkout has one completion, no exit after success and no cross-tenant events',
    () async {
      var session = _session('a');
      final queue = JourneyQueue();
      final service = ProductJourney(
        readSession: () => session,
        readEnvironment: AppEnvironment.remoteDefault,
        tokenStorage: _Tokens(),
        client: MockClient((_) async => http.Response('{}', 500)),
        queue: queue,
      );
      addTearDown(service.dispose);
      final attempt = service.beginCheckout();
      attempt.fail();
      attempt.complete();
      attempt.complete();
      attempt.exit();
      final events = await queue.batch(_scope('a'));
      expect(events.map((event) => event['name']), [
        'checkout_started',
        'checkout_failed',
        'checkout_completed',
      ]);
      expect(events.map((event) => event['attemptId']).toSet(), {attempt.id});
      final otherAttempt = service.beginCheckout();
      session = _session('b');
      otherAttempt.complete();
      expect(await queue.batch(_scope('b')), isEmpty);
    },
  );
}

class _Tokens implements AuthTokenStorage {
  Future<String?>? pending;
  @override
  Future<String?> readAccessToken() => pending ?? Future.value('token');
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<AuthClientContext?> readClientContext() async => null;
  @override
  Future<void> clear() async {}
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}
  @override
  Future<AuthClientContext> ensureClientContext({
    required String clientType,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async => const AuthClientContext(
    clientType: 'mobile_app',
    clientInstanceId: 'device',
  );
}
