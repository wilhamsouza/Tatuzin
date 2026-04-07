import 'dart:async';

import '../models/admin_models.dart';
import '../network/admin_api_client.dart';
import '../network/admin_api_service.dart';
import 'admin_auth_storage.dart';
import 'package:flutter/foundation.dart';
import 'admin_debug_log.dart';

class AdminAuthController extends ChangeNotifier {
  AdminAuthController({
    required AdminApiService apiService,
    required AdminAuthStorage authStorage,
  }) : _apiService = apiService,
       _authStorage = authStorage {
    _authStorage.addListener(_handleStorageChanged);
    unawaited(restoreSession());
  }

  final AdminApiService _apiService;
  final AdminAuthStorage _authStorage;

  AdminSession? _session;
  bool _isRestoring = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  AdminSession? get session => _session;
  bool get isAuthenticated => _session != null;
  bool get isPlatformAdmin => _session?.user.isPlatformAdmin == true;
  bool get isRestoring => _isRestoring;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  @override
  void dispose() {
    _authStorage.removeListener(_handleStorageChanged);
    super.dispose();
  }

  Future<void> restoreSession() async {
    _isRestoring = true;
    adminDebugLog('auth.controller.restore.started');
    notifyListeners();

    try {
      final accessToken = await _authStorage.readAccessToken();
      if (accessToken == null || accessToken.trim().isEmpty) {
        _session = null;
        _errorMessage = null;
        adminDebugLog('auth.controller.restore.skipped', {
          'reason': 'access_token_missing',
        });
        return;
      }

      final snapshot = await _authStorage.readSessionSnapshot();
      if (snapshot != null) {
        adminDebugLog('auth.controller.restore.snapshot_found', {
          'userEmail': snapshot.user.email,
          'isPlatformAdmin': snapshot.user.isPlatformAdmin,
          'sessionId': snapshot.activeSession?.id,
        });
      }

      _session = await _apiService.restoreSession(accessToken.trim());
      await _authStorage.saveSessionSnapshot(_session!);
      _errorMessage = null;
      adminDebugLog('auth.controller.restore.succeeded', {
        'userEmail': _session?.user.email,
        'isPlatformAdmin': _session?.user.isPlatformAdmin,
        'sessionId': _session?.activeSession?.id,
      });
    } catch (error) {
      _session = null;
      _errorMessage = _describeError(error);
      adminDebugLog('auth.controller.restore.failed', {
        'errorType': error.runtimeType.toString(),
        'errorMessage': error.toString(),
      });
      await _authStorage.clear();
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isSubmitting = true;
    _errorMessage = null;
    adminDebugLog('auth.controller.login.started', {
      'email': email.trim(),
    });
    notifyListeners();

    try {
      final session = await _apiService.login(email: email, password: password);
      adminDebugLog('auth.controller.login.response_ready', {
        'userEmail': session.user.email,
        'isPlatformAdmin': session.user.isPlatformAdmin,
        'tokenType': session.tokenType,
        'sessionId': session.activeSession?.id,
      });
      final refreshToken = session.refreshToken;
      if (refreshToken == null || refreshToken.trim().isEmpty) {
        throw const AdminApiException(
          message: 'A API administrativa nao retornou um refresh token valido.',
          statusCode: 401,
          code: 'ADMIN_REFRESH_TOKEN_MISSING',
        );
      }
      await _authStorage.saveTokens(
        accessToken: session.accessToken,
        refreshToken: refreshToken,
      );
      await _authStorage.saveSessionSnapshot(session);
      _session = session;
      adminDebugLog('auth.controller.login.succeeded', {
        'userEmail': session.user.email,
        'isPlatformAdmin': session.user.isPlatformAdmin,
        'sessionId': session.activeSession?.id,
      });
      return true;
    } catch (error) {
      _session = null;
      _errorMessage = _describeError(error);
      adminDebugLog('auth.controller.login.failed', {
        'errorType': error.runtimeType.toString(),
        'errorMessage': error.toString(),
      });
      await _authStorage.clear();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final accessToken = _session?.accessToken;
    adminDebugLog('auth.controller.logout.started', {
      'hasAccessToken': accessToken != null && accessToken.trim().isNotEmpty,
    });
    try {
      if (accessToken != null && accessToken.trim().isNotEmpty) {
        await _apiService.logout(accessToken);
      }
    } catch (_) {
      // O logout local precisa prevalecer mesmo se a API estiver indisponivel.
    } finally {
      await _authStorage.clear();
      _session = null;
      _errorMessage = null;
      adminDebugLog('auth.controller.logout.completed');
      notifyListeners();
    }
  }

  String _describeError(Object error) {
    if (error is AdminApiException) {
      return error.message;
    }
    if (error is FormatException) {
      return 'A API respondeu, mas o painel nao conseguiu ler a sessao administrativa.';
    }
    return 'Nao foi possivel concluir a autenticacao administrativa agora.';
  }

  void _handleStorageChanged() {
    unawaited(_syncSessionWithStorage());
  }

  Future<void> _syncSessionWithStorage() async {
    if (_isSubmitting || _isRestoring) {
      adminDebugLog('auth.controller.storage_sync.skipped', {
        'isSubmitting': _isSubmitting,
        'isRestoring': _isRestoring,
      });
      return;
    }

    final accessToken = await _authStorage.readAccessToken();
    if (accessToken != null && accessToken.trim().isNotEmpty) {
      adminDebugLog('auth.controller.storage_sync.kept_session', {
        'hasAccessToken': true,
      });
      return;
    }

    if (_session == null && _errorMessage == null) {
      return;
    }

    _session = null;
    _errorMessage = 'Sua sessao administrativa terminou. Faca login novamente.';
    adminDebugLog('auth.controller.storage_sync.session_cleared', {
      'reason': 'access_token_removed',
    });
    notifyListeners();
  }
}
