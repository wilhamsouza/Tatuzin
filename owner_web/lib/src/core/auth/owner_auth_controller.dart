import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/owner_models.dart';
import '../network/owner_api_service.dart';
import 'owner_auth_storage.dart';
import 'owner_debug_log.dart';

class OwnerAuthController extends ChangeNotifier {
  OwnerAuthController({
    required OwnerApiService apiService,
    required OwnerAuthStorage authStorage,
    bool restoreOnStart = true,
  }) : _apiService = apiService,
       _authStorage = authStorage {
    _authStorage.addListener(_handleStorageChanged);
    if (restoreOnStart) {
      unawaited(restoreSession());
    } else {
      _isRestoring = false;
    }
  }

  final OwnerApiService _apiService;
  final OwnerAuthStorage _authStorage;

  OwnerSession? _session;
  bool _isRestoring = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  OwnerSession? get session => _session;
  bool get isAuthenticated => _session != null;
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
    _errorMessage = null;
    ownerDebugLog('auth.controller.restore.started');
    notifyListeners();

    try {
      final accessToken = await _authStorage.readAccessToken();
      if (accessToken == null || accessToken.trim().isEmpty) {
        _session = null;
        ownerDebugLog('auth.controller.restore.skipped', {
          'hasAccessToken': false,
        });
        return;
      }
      final snapshot = await _authStorage.readSessionSnapshot();
      if (snapshot != null) {
        ownerDebugLog('auth.controller.restore.snapshot_found', {
          'companyId': snapshot.company.id,
          'membershipRole': snapshot.membership.role,
        });
      }
      final session = await _apiService.restoreSession(accessToken.trim());
      _assertOwnerShellAccess(session);
      await _authStorage.saveSessionSnapshot(session);
      _session = session;
      _errorMessage = null;
      ownerDebugLog('auth.controller.restore.succeeded', {
        'companyId': session.company.id,
        'membershipRole': session.membership.role,
      });
    } catch (error) {
      _session = null;
      _errorMessage = describeOwnerError(error);
      ownerDebugLog('auth.controller.restore.failed', {
        'errorType': error.runtimeType.toString(),
      });
      await _authStorage.clear();
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _isSubmitting = true;
    _errorMessage = null;
    ownerDebugLog('auth.controller.login.started', {'email': email.trim()});
    notifyListeners();

    try {
      final session = await _apiService.login(email: email, password: password);
      final refreshToken = session.refreshToken;
      if (refreshToken == null || refreshToken.trim().isEmpty) {
        throw const OwnerApiException(
          message: 'A sessão não pôde ser iniciada corretamente.',
          statusCode: 401,
          code: 'OWNER_REFRESH_TOKEN_MISSING',
        );
      }
      await _authStorage.saveTokens(
        accessToken: session.accessToken,
        refreshToken: refreshToken,
      );
      _assertOwnerShellAccess(session);
      await _authStorage.saveSessionSnapshot(session);
      _session = session;
      _errorMessage = null;
      ownerDebugLog('auth.controller.login.succeeded', {
        'companyId': session.company.id,
        'membershipRole': session.membership.role,
      });
      return true;
    } catch (error) {
      _session = null;
      _errorMessage = describeOwnerError(error);
      ownerDebugLog('auth.controller.login.failed', {
        'errorType': error.runtimeType.toString(),
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
    ownerDebugLog('auth.controller.logout.started', {
      'hasAccessToken': accessToken != null && accessToken.trim().isNotEmpty,
    });
    try {
      if (accessToken != null && accessToken.trim().isNotEmpty) {
        await _apiService.logout(accessToken);
      }
    } catch (_) {
      // Logout local prevalece quando a rede estiver indisponivel.
    } finally {
      await _authStorage.clear();
      _session = null;
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _handleStorageChanged() {
    unawaited(_syncSessionWithStorage());
  }

  Future<void> _syncSessionWithStorage() async {
    if (_isSubmitting || _isRestoring) {
      return;
    }
    final accessToken = await _authStorage.readAccessToken();
    if (accessToken != null && accessToken.trim().isNotEmpty) {
      return;
    }
    if (_session == null && _errorMessage == null) {
      return;
    }
    _session = null;
    _errorMessage = 'Sua sessão terminou. Entre novamente.';
    notifyListeners();
  }
}

void _assertOwnerShellAccess(OwnerSession session) {
  final role = session.membership.role.trim().toUpperCase();
  if (role == 'OWNER' || role == 'ADMIN') {
    return;
  }
  throw const OwnerApiException(
    message: 'Voce nao tem permissao para acessar este painel.',
    statusCode: 403,
    code: 'OWNER_PANEL_ACCESS_REQUIRED',
  );
}

String describeOwnerError(Object error) {
  if (error is OwnerApiException) {
    switch (error.code) {
      case 'OWNER_REQUIRED':
        return 'Apenas o dono da empresa pode acessar este painel.';
      case 'OWNER_PANEL_ACCESS_REQUIRED':
        return 'Você não tem permissão para acessar este painel.';
      case 'FEATURE_NOT_AVAILABLE':
        return 'Painel da empresa está disponível no plano PRO.';
      case 'OWNER_AUTH_REQUIRED':
      case 'AUTH_REQUIRED':
      case 'SESSION_NOT_FOUND':
        return 'Sua sessão expirou. Entre novamente.';
      default:
        if (error.statusCode == 403) {
          return 'Você não tem permissão para acessar este painel.';
        }
        if (error.statusCode == 401) {
          return 'Sua sessão expirou. Entre novamente.';
        }
        return error.message;
    }
  }
  if (error is TimeoutException) {
    return 'Não foi possível carregar o painel agora. Tente novamente.';
  }
  if (error is FormatException) {
    return 'A API respondeu, mas o painel não conseguiu ler os dados.';
  }
  return 'Não foi possível carregar o painel agora. Tente novamente.';
}
