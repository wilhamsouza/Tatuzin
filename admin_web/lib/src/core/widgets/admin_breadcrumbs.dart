import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminBreadcrumbs extends StatelessWidget {
  const AdminBreadcrumbs({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final crumbs = _crumbsForLocation(location);
    if (crumbs.length <= 1) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < crumbs.length; index++) ...[
          if (index > 0)
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          _BreadcrumbChip(
            crumb: crumbs[index],
            isLast: index == crumbs.length - 1,
          ),
        ],
      ],
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({required this.crumb, required this.isLast});

  final _Breadcrumb crumb;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: isLast
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
      fontWeight: isLast ? FontWeight.w800 : FontWeight.w600,
    );
    if (isLast || crumb.route == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(crumb.label, style: style),
      );
    }
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => context.go(crumb.route!),
      child: Text(crumb.label, style: style),
    );
  }
}

class _Breadcrumb {
  const _Breadcrumb(this.label, [this.route]);

  final String label;
  final String? route;
}

List<_Breadcrumb> _crumbsForLocation(String location) {
  final uri = Uri.tryParse(location);
  final path = uri?.path ?? location;
  final segments = path
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);

  if (segments.isEmpty || path == '/dashboard') {
    return const [_Breadcrumb('Plataforma', '/dashboard')];
  }

  if (segments.first == 'companies') {
    if (segments.length == 1) {
      return const [
        _Breadcrumb('Plataforma', '/dashboard'),
        _Breadcrumb('Empresas'),
      ];
    }
    final companyId = segments[1];
    final companyRoute = '/companies/$companyId';
    final crumbs = <_Breadcrumb>[
      const _Breadcrumb('Plataforma', '/dashboard'),
      const _Breadcrumb('Empresas', '/companies'),
      _Breadcrumb('Empresa', companyRoute),
    ];
    if (segments.length >= 3) {
      crumbs.add(_Breadcrumb(_companySectionLabel(segments[2])));
    }
    return crumbs;
  }

  if (segments.first == 'billing') {
    return [
      const _Breadcrumb('Plataforma', '/dashboard'),
      const _Breadcrumb('Billing', '/billing'),
      if (segments.length > 1) const _Breadcrumb('Empresa'),
    ];
  }

  if (segments.first == 'licenses') {
    return [
      const _Breadcrumb('Plataforma', '/dashboard'),
      const _Breadcrumb('Licencas', '/licenses'),
      if (segments.length > 1) const _Breadcrumb('Empresa'),
    ];
  }

  if (segments.first == 'sync') {
    return [
      const _Breadcrumb('Plataforma', '/dashboard'),
      const _Breadcrumb('Sync Center', '/sync'),
      if (segments.length > 1) const _Breadcrumb('Empresa'),
      if (segments.length > 2) _Breadcrumb(_syncDetailLabel(segments[2])),
    ];
  }

  if (segments.first == 'admin' &&
      segments.length > 1 &&
      segments[1] == 'permissions') {
    return const [
      _Breadcrumb('Plataforma', '/dashboard'),
      _Breadcrumb('Permissoes administrativas'),
    ];
  }

  return [
    const _Breadcrumb('Plataforma', '/dashboard'),
    _Breadcrumb(_topLevelLabel(segments.first)),
  ];
}

String _companySectionLabel(String segment) {
  switch (segment) {
    case 'support':
      return 'Central de suporte';
    case 'users':
    case 'employees':
      return 'Usuarios e funcionarios';
    case 'devices':
    case 'sessions':
      return 'Dispositivos e sessoes';
    case 'license':
      return 'Licenca e billing';
    case 'sync':
      return 'Sync Center';
    default:
      return 'Secao';
  }
}

String _syncDetailLabel(String segment) {
  switch (segment) {
    case 'events':
      return 'Evento';
    case 'conflicts':
      return 'Conflito';
    default:
      return 'Detalhe';
  }
}

String _topLevelLabel(String segment) {
  switch (segment) {
    case 'devices':
      return 'Dispositivos e sessoes';
    case 'audit':
      return 'Auditoria';
    case 'plans':
      return 'Planos';
    case 'permissions':
      return 'Permissoes administrativas';
    case 'sync-health':
      return 'Saude do sync';
    case 'management':
      return 'Gerencial';
    default:
      return segment;
  }
}
