import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../config/app_data_mode.dart';
import '../constants/app_constants.dart';
import '../session/app_session.dart';
import '../session/auth_token_storage.dart';
import '../session/session_provider.dart';
import '../utils/id_generator.dart';
import 'journey_queue.dart';

enum JourneyEvent {
  registrationCompleted('registration_completed'),
  productCreated('product_created'),
  cashOpened('cash_opened'),
  checkoutStarted('checkout_started'),
  checkoutCompleted('checkout_completed'),
  checkoutExited('checkout_exited'),
  checkoutFailed('checkout_failed'),
  plansViewed('plans_viewed'),
  subscriptionStarted('subscription_started');

  const JourneyEvent(this.key);
  final String key;
}

final productJourneyProvider = Provider<ProductJourney>((ref) {
  final client = http.Client();
  final service = ProductJourney(
    readSession: () => ref.read(appSessionProvider),
    readEnvironment: () => ref.read(appEnvironmentProvider),
    tokenStorage: ref.read(authTokenStorageProvider),
    client: client,
  );
  ref.onDispose(() {
    service.dispose();
    client.close();
  });
  return service;
});

class ProductJourney {
  ProductJourney({
    required this.readSession,
    required this.readEnvironment,
    required this.tokenStorage,
    required this.client,
    JourneyQueue? queue,
  }) : queue = queue ?? JourneyQueue();

  final AppSession Function() readSession;
  final AppEnvironment Function() readEnvironment;
  final AuthTokenStorage tokenStorage;
  final http.Client client;
  final JourneyQueue queue;
  Timer? _timer;
  bool _disposed = false;
  bool _flushing = false;

  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => flush());
    unawaited(_startQueue());
  }

  Future<void> _startQueue() async {
    try {
      await queue.pruneExpired();
      await flush();
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  String _scope(AppSession session) => base64Url.encode(
    utf8.encode(
      jsonEncode([session.company.remoteId!, session.clientInstanceId!]),
    ),
  );

  bool _samePrincipal(AppSession original) {
    if (_disposed) return false;
    final current = readSession();
    return current.isRemoteAuthenticated &&
        current.company.remoteId == original.company.remoteId &&
        current.user.remoteId == original.user.remoteId &&
        current.clientInstanceId == original.clientInstanceId;
  }

  /// Captures identity synchronously; all IO is best-effort and never awaited by sales.
  void record(
    JourneyEvent name, {
    String? attemptId,
    int? durationMs,
    AppSession? owner,
  }) {
    if (_disposed) return;
    final session = owner ?? readSession();
    if (!_samePrincipal(session)) return;
    if (!session.isRemoteAuthenticated || !session.hasOperationalIdentity) {
      return;
    }
    final event = <String, dynamic>{
      'eventId': IdGenerator.next(),
      'name': name.key,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': AppConstants.appVersion,
      'plan': session.plan.key,
      'experienceProfile': session.company.experienceProfile.key,
      if (attemptId != null) 'attemptId': attemptId,
      if (durationMs != null) 'durationMs': durationMs.clamp(0, 2147483647),
    };
    unawaited(_enqueue(_scope(session), event));
  }

  JourneyCheckoutAttempt beginCheckout() =>
      JourneyCheckoutAttempt(this, readSession());

  Future<void> _enqueue(String scope, Map<String, dynamic> event) async {
    try {
      await queue.append(scope, event);
      await flush();
    } catch (_) {
      // Storage, plugin, and network failures must not affect the business action.
    }
  }

  Future<void> flush() async {
    if (_disposed || _flushing) return;
    _flushing = true;
    try {
      final session = readSession();
      final environment = readEnvironment();
      if (!session.isRemoteAuthenticated ||
          !session.hasOperationalIdentity ||
          session.isOfflineFallback ||
          !environment.dataMode.allowsRemoteRead) {
        return;
      }
      final uri = environment.endpointConfig.uriFor('/product-journey/events');
      if (uri == null) return;
      final scope = _scope(session);
      final events = await queue.batch(scope);
      if (events.isEmpty) return;
      final token = await tokenStorage.readAccessToken();
      if (token == null || !_samePrincipal(session)) return;
      // Dedicated HTTP client: telemetry errors cannot refresh/revoke the app session.
      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'X-Client-Instance-Id': session.clientInstanceId!,
            },
            body: jsonEncode({
              'companyId': session.company.remoteId,
              'events': events,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final ids = (body['acknowledgedEventIds'] as List)
          .whereType<String>()
          .toSet();
      final sentIds = events.map((event) => event['eventId'] as String).toSet();
      await queue.acknowledge(scope, ids.intersection(sentIds));
    } catch (_) {
      // Keep the queue for the next foreground/resume attempt.
    } finally {
      _flushing = false;
    }
  }
}

class JourneyCheckoutAttempt {
  JourneyCheckoutAttempt(this._journey, this._owner) {
    _journey.record(JourneyEvent.checkoutStarted, attemptId: id, owner: _owner);
  }

  final ProductJourney _journey;
  final AppSession _owner;
  final String id = IdGenerator.next();
  final Stopwatch _watch = Stopwatch()..start();
  bool _finished = false;

  void complete() {
    if (_finished) return;
    _finished = true;
    _watch.stop();
    _journey.record(
      JourneyEvent.checkoutCompleted,
      attemptId: id,
      durationMs: _watch.elapsedMilliseconds,
      owner: _owner,
    );
  }

  void fail() {
    if (_finished) return;
    _journey.record(JourneyEvent.checkoutFailed, attemptId: id, owner: _owner);
  }

  void exit() {
    if (_finished) return;
    _finished = true;
    _watch.stop();
    _journey.record(JourneyEvent.checkoutExited, attemptId: id, owner: _owner);
  }
}
