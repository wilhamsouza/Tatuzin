import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin/app/core/session/auth_token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accessTokenKey = 'session.remote_access_token';
  const refreshTokenKey = 'session.remote_refresh_token';

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('saveTokens grava tokens no storage seguro e remove legado', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      accessTokenKey: 'legacy-access',
      refreshTokenKey: 'legacy-refresh',
    });
    final secureStore = _MemorySecureTokenStore();
    final storage = SecureAuthTokenStorage(secureTokenStore: secureStore);

    await storage.saveTokens(
      accessToken: 'secure-access',
      refreshToken: 'secure-refresh',
    );

    expect(await secureStore.read(key: accessTokenKey), 'secure-access');
    expect(await secureStore.read(key: refreshTokenKey), 'secure-refresh');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(accessTokenKey), isNull);
    expect(preferences.getString(refreshTokenKey), isNull);
  });

  test(
    'readAccessToken le token seguro quando existe e remove sobra legada',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        accessTokenKey: 'legacy-access',
      });
      final secureStore = _MemorySecureTokenStore(
        values: <String, String>{accessTokenKey: 'secure-access'},
      );
      final storage = SecureAuthTokenStorage(secureTokenStore: secureStore);

      expect(await storage.readAccessToken(), 'secure-access');

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(accessTokenKey), isNull);
    },
  );

  test(
    'readRefreshToken le token seguro quando existe e remove sobra legada',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        refreshTokenKey: 'legacy-refresh',
      });
      final secureStore = _MemorySecureTokenStore(
        values: <String, String>{refreshTokenKey: 'secure-refresh'},
      );
      final storage = SecureAuthTokenStorage(secureTokenStore: secureStore);

      expect(await storage.readRefreshToken(), 'secure-refresh');

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(refreshTokenKey), isNull);
    },
  );

  test('readAccessToken migra token legado para storage seguro', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      accessTokenKey: 'legacy-access',
    });
    final secureStore = _MemorySecureTokenStore();
    final storage = SecureAuthTokenStorage(secureTokenStore: secureStore);

    expect(await storage.readAccessToken(), 'legacy-access');
    expect(await secureStore.read(key: accessTokenKey), 'legacy-access');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(accessTokenKey), isNull);
  });

  test('readRefreshToken migra token legado para storage seguro', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      refreshTokenKey: 'legacy-refresh',
    });
    final secureStore = _MemorySecureTokenStore();
    final storage = SecureAuthTokenStorage(secureTokenStore: secureStore);

    expect(await storage.readRefreshToken(), 'legacy-refresh');
    expect(await secureStore.read(key: refreshTokenKey), 'legacy-refresh');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(refreshTokenKey), isNull);
  });

  test(
    'token legado so e removido apos confirmacao de escrita segura',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        accessTokenKey: 'legacy-access',
      });
      final secureStore = _MemorySecureTokenStore(dropWrites: true);
      final storage = SecureAuthTokenStorage(secureTokenStore: secureStore);

      await expectLater(storage.readAccessToken, throwsA(isA<StateError>()));

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(accessTokenKey), 'legacy-access');
      expect(await secureStore.read(key: accessTokenKey), isNull);
    },
  );

  test('clear remove tokens seguros e tokens legados', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      accessTokenKey: 'legacy-access',
      refreshTokenKey: 'legacy-refresh',
    });
    final secureStore = _MemorySecureTokenStore(
      values: <String, String>{
        accessTokenKey: 'secure-access',
        refreshTokenKey: 'secure-refresh',
      },
    );
    final storage = SecureAuthTokenStorage(secureTokenStore: secureStore);

    await storage.clear();

    expect(await secureStore.read(key: accessTokenKey), isNull);
    expect(await secureStore.read(key: refreshTokenKey), isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(accessTokenKey), isNull);
    expect(preferences.getString(refreshTokenKey), isNull);
  });
}

class _MemorySecureTokenStore implements SecureTokenStore {
  _MemorySecureTokenStore({
    Map<String, String> values = const <String, String>{},
    this.dropWrites = false,
  }) : _values = Map<String, String>.from(values);

  final Map<String, String> _values;
  final bool dropWrites;

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    if (!dropWrites) {
      _values[key] = value;
    }
  }
}
