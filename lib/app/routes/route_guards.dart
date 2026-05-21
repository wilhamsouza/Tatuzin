import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';

import '../core/database/app_database.dart';
import '../core/session/app_session.dart';
import '../core/session/auth_provider.dart';
import 'route_names.dart';

String? appRouteRedirect({
  required AppSession session,
  required AppStartupState? startupState,
  required GoRouterState state,
  bool initialPasswordChangeRequired = false,
}) {
  final path = state.uri.path;

  if (initialPasswordChangeRequired) {
    return path == AppRoutePaths.changeInitialPassword
        ? null
        : AppRoutePaths.changeInitialPassword;
  }

  if (isPublicRoutePath(path)) {
    if (path == AppRoutePaths.login &&
        session.hasOperationalIdentity &&
        startupState?.isSuccess == true) {
      return AppRoutePaths.dashboard;
    }
    return null;
  }

  if (!session.hasOperationalIdentity) {
    return AppRoutePaths.login;
  }

  if (path == AppRoutePaths.permissionDenied) {
    return null;
  }

  if (!canAccessRoutePath(session, state)) {
    return AppRoutePaths.permissionDenied;
  }

  return null;
}

bool isPublicRoutePath(String path) {
  return path == AppRoutePaths.login ||
      path == AppRoutePaths.register ||
      path == AppRoutePaths.forgotPassword ||
      path == AppRoutePaths.resetPassword ||
      path == AppRoutePaths.changeInitialPassword;
}

bool canAccessRoutePath(AppSession session, GoRouterState state) {
  final path = state.uri.path;
  final required = requiredAnyPermissionForPath(path);
  if (required.isEmpty) {
    if (_isOwnerOnlyPath(path)) {
      return session.isCompanyOwner || _effectiveRole(session) == 'ADMIN';
    }
    return true;
  }

  if (path.startsWith('/funcionarios/') && path.endsWith('/atividade')) {
    final ownEmployeeId = session.employee?.id;
    final requestedEmployeeId = state.pathParameters['employeeId'];
    if (ownEmployeeId != null &&
        ownEmployeeId.isNotEmpty &&
        requestedEmployeeId == ownEmployeeId) {
      return true;
    }
  }

  return required.any(session.canAccessPermission);
}

Set<String> requiredAnyPermissionForPath(String path) {
  if (path == AppRoutePaths.dashboard || path == AppRoutePaths.more) {
    return const <String>{};
  }
  if (path.startsWith('/vendas') ||
      path.startsWith('/carrinho') ||
      path.startsWith('/checkout') ||
      path.startsWith('/pedidos')) {
    return const {'sales.create'};
  }
  if (path.startsWith('/caixa')) {
    return const {'cash.open', 'cash.close', 'cash.withdraw'};
  }
  if (path.startsWith('/historico-vendas') ||
      path.startsWith('/comprovantes')) {
    return const {'sales.create', 'reports.basic', 'reports.advanced'};
  }
  if (path.startsWith('/clientes')) {
    return const {'customers.read', 'customers.write'};
  }
  if (path.startsWith('/produtos/form') || path.startsWith('/categorias')) {
    return const {'products.write'};
  }
  if (path.startsWith('/produtos')) {
    return const {'products.read', 'products.write'};
  }
  if (path.startsWith('/estoque/ajustes')) {
    return const {'stock.adjust'};
  }
  if (path.startsWith('/estoque')) {
    return const {'stock.adjust', 'reports.advanced'};
  }
  if (path.startsWith('/fiado')) {
    return const {'fiado.read', 'fiado.receive'};
  }
  if (path.startsWith('/custos') ||
      path.startsWith('/compras') ||
      path.startsWith('/fornecedores')) {
    return const {'reports.advanced'};
  }
  if (path.startsWith('/insumos')) {
    return const {'stock.adjust', 'products.write'};
  }
  if (path == AppRoutePaths.reports ||
      path == AppRoutePaths.salesReports ||
      path == AppRoutePaths.cashReports) {
    return const {'reports.basic', 'reports.advanced'};
  }
  if (path.startsWith('/relatorios')) {
    return const {'reports.advanced'};
  }
  if (path == AppRoutePaths.employees) {
    return const {'employees.manage'};
  }
  if (path == AppRoutePaths.employeeActivity ||
      (path.startsWith('/funcionarios/') && path.endsWith('/atividade'))) {
    return const {'employees.manage', 'reports.advanced'};
  }
  return const <String>{};
}

bool _isOwnerOnlyPath(String path) {
  return path == AppRoutePaths.accountCloud ||
      path == AppRoutePaths.company ||
      path == AppRoutePaths.settings ||
      path == AppRoutePaths.subscription ||
      path == AppRoutePaths.backup;
}

String _effectiveRole(AppSession session) {
  return (session.employee?.role ?? session.membership?.role ?? '')
      .trim()
      .toUpperCase();
}

bool canOpenTechnicalRoute(AuthStatusSnapshot authStatus) {
  return kDebugMode ||
      authStatus.isPlatformAdmin ||
      authStatus.isSupportProfile;
}

bool canOpenAdminRoute(AuthStatusSnapshot authStatus) {
  return authStatus.isRemoteAuthenticated && canOpenTechnicalRoute(authStatus);
}

String? redirectToAccountUnless(bool allowed) {
  return allowed ? null : AppRoutePaths.accountCloud;
}
