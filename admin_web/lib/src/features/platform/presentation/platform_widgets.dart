import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/admin_api_client.dart';
import '../../../core/utils/admin_formatters.dart';
import '../data/platform_api.dart';

Uri platformLocation(BuildContext context, String fallback) =>
    GoRouter.maybeOf(context)?.routeInformationProvider.value.uri ??
    Uri(path: fallback);

void platformNavigate(BuildContext context, String location) =>
    context.go(location);

String platformDate(Object? value) => value is String
    ? AdminFormatters.formatDateTime(DateTime.tryParse(value))
    : 'Sem informação recente';
String platformMoney(Object? value) =>
    AdminFormatters.formatCurrencyFromCents(platformInt(value));
String platformCurrency(Object? value, Object? currency) =>
    NumberFormat.simpleCurrency(
      locale: 'pt_BR',
      name: platformText(currency, 'BRL'),
    ).format(platformInt(value) / 100);
String platformError(Object error) {
  if (error is AdminApiException) {
    if (error.statusCode == 409 &&
        (error.code?.startsWith('ADMIN_OPERATION_') == true ||
            error.code?.startsWith('ADMIN_PREVIEW_') == true)) {
      return error.message;
    }
    if (error.statusCode == 409) {
      return 'Este registro mudou em outra sessão. Atualize os dados e repita sua alteração.';
    }
    if (error.statusCode == 403) {
      return 'Você não tem permissão para acessar este recurso.';
    }
    if (error.statusCode == 401) return 'Sua sessão expirou. Entre novamente.';
    return error.message;
  }
  return 'Não foi possível acessar os dados. Verifique sua conexão e tente novamente.';
}

String platformStatus(String value) => switch (value) {
  'ACTIVE' => 'Ativa',
  'EXPIRED' => 'Vencida',
  'SUSPENDED' => 'Suspensa',
  'PAID' => 'Paga',
  'PENDING' => 'Pendente',
  'OPEN' => 'Aberto',
  'IN_PROGRESS' => 'Em atendimento',
  'WAITING' => 'Aguardando',
  'RESOLVED' => 'Resolvido',
  'CRITICAL' || 'critical' => 'Crítica',
  'HIGH' => 'Alta',
  'NORMAL' => 'Normal',
  'LOW' => 'Baixa',
  'warning' => 'Atenção',
  _ => value,
};

class PlatformPage extends StatelessWidget {
  const PlatformPage({super.key, required this.children, this.storageKey});
  final List<Widget> children;
  final String? storageKey;
  @override
  Widget build(BuildContext context) => ListView(
    key: PageStorageKey(storageKey ?? runtimeType.toString()),
    padding: const EdgeInsets.only(bottom: 32),
    children: [
      for (final child in children) ...[child, const SizedBox(height: 20)],
    ],
  );
}

class PlatformHeader extends StatelessWidget {
  const PlatformHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 720 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.5) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            text,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: text),
          const SizedBox(width: 20),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    },
  );
}

class PlatformPanel extends StatelessWidget {
  const PlatformPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (action != null) action!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

class PlatformState extends StatelessWidget {
  const PlatformState({
    super.key,
    required this.message,
    this.onRetry,
    this.error = false,
  });
  final String message;
  final VoidCallback? onRetry;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.info_outline_rounded : Icons.inbox_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(message),
        if (onRetry != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ],
    ),
  );
}

class PlatformResourceView extends ConsumerWidget {
  const PlatformResourceView({
    super.key,
    required this.resource,
    required this.builder,
  });
  final String resource;
  final Widget Function(PlatformMap data) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(platformResourceProvider(resource))
      .when(
        data: builder,
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: LinearProgressIndicator(),
        ),
        error: (error, _) => PlatformState(
          message: platformError(error),
          error: true,
          onRetry: () => ref.invalidate(platformResourceProvider(resource)),
        ),
      );
}

class PlatformGrid extends StatelessWidget {
  const PlatformGrid({super.key, required this.children, this.minWidth = 250});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
      var columns = (constraints.maxWidth / (minWidth * scale)).floor().clamp(
        1,
        6,
      );
      if (children.isNotEmpty && columns > children.length) {
        columns = children.length;
      }
      if (children.length == 6 && columns > 3 && columns < 6) columns = 3;
      final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class PlatformMetric extends StatelessWidget {
  const PlatformMetric({
    super.key,
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class PlatformRow extends StatelessWidget {
  const PlatformRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 520 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.5;
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(subtitle),
        ],
      );
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text,
                    if (trailing != null) ...[
                      const SizedBox(height: 10),
                      trailing!,
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: text),
                    if (trailing != null) ...[
                      const SizedBox(width: 16),
                      trailing!,
                    ],
                  ],
                ),
        ),
      );
    },
  );
}

class PlatformPager extends StatelessWidget {
  const PlatformPager({
    super.key,
    required this.page,
    required this.total,
    required this.pageSize,
    required this.onPage,
  });
  final int page;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        '$total registros · Página $page de ${(total / pageSize).ceil().clamp(1, 1000000)}',
      ),
      OutlinedButton(
        onPressed: page > 1 ? () => onPage(page - 1) : null,
        child: const Text('Anterior'),
      ),
      OutlinedButton(
        onPressed: page * pageSize < total ? () => onPage(page + 1) : null,
        child: const Text('Próxima'),
      ),
    ],
  );
}
