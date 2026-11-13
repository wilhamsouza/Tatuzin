import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Independent of the operational database and its sync queue.
class JourneyQueue {
  Future<void> _pending = Future.value();
  static const maxEvents = 1000;
  static const retention = Duration(days: 90);

  String _key(String scope) => 'product_journey.v1.$scope';

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .where((event) {
            final at = DateTime.tryParse(event['occurredAt'] as String? ?? '');
            return at != null && at.isAfter(DateTime.now().subtract(retention));
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> append(String scope, Map<String, dynamic> event) =>
      _serialize(() async {
        final preferences = await SharedPreferences.getInstance();
        final events = _decode(preferences.getString(_key(scope)))..add(event);
        final bounded = events.length > maxEvents
            ? events.sublist(events.length - maxEvents)
            : events;
        await preferences.setString(_key(scope), jsonEncode(bounded));
      });

  Future<void> pruneExpired() => _serialize(() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith('product_journey.v1.'),
    )) {
      final events = _decode(preferences.getString(key));
      if (events.isEmpty) {
        await preferences.remove(key);
      } else {
        await preferences.setString(key, jsonEncode(events));
      }
    }
  });

  Future<List<Map<String, dynamic>>> batch(String scope) =>
      _serialize(() async {
        final preferences = await SharedPreferences.getInstance();
        final events = _decode(preferences.getString(_key(scope)));
        // Persist pruning even if there is nothing to send.
        await preferences.setString(_key(scope), jsonEncode(events));
        return events.take(50).toList();
      });

  Future<void> acknowledge(String scope, Set<String> ids) =>
      _serialize(() async {
        final preferences = await SharedPreferences.getInstance();
        final events = _decode(
          preferences.getString(_key(scope)),
        ).where((event) => !ids.contains(event['eventId'])).toList();
        if (events.isEmpty) {
          await preferences.remove(_key(scope));
        } else {
          await preferences.setString(_key(scope), jsonEncode(events));
        }
      });
}
