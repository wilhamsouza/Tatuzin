import 'package:flutter/material.dart';
import '../core/session/app_session.dart';
import 'route_guards.dart';
import 'route_names.dart';

class AppDestination {
  const AppDestination(this.label, this.path, this.icon, this.branch);
  final String label;
  final String path;
  final IconData icon;
  final int branch;
  String get routeName => switch (branch) {
    0 => AppRouteNames.dashboard,
    1 => AppRouteNames.products,
    2 => AppRouteNames.sales,
    3 => AppRouteNames.activity,
    _ => AppRouteNames.profile,
  };
}

const appDestinations = [
  AppDestination('Início', AppRoutePaths.dashboard, Icons.home_outlined, 0),
  AppDestination(
    'Produtos',
    AppRoutePaths.products,
    Icons.inventory_2_outlined,
    1,
  ),
  AppDestination('Vender', AppRoutePaths.sales, Icons.add_rounded, 2),
  AppDestination(
    'Atividade',
    AppRoutePaths.activity,
    Icons.receipt_long_outlined,
    3,
  ),
  AppDestination(
    'Perfil',
    AppRoutePaths.profile,
    Icons.person_outline_rounded,
    4,
  ),
];

List<AppDestination> destinationsFor(AppSession session) => appDestinations
    .where((destination) => canAccessNavigationPath(session, destination.path))
    .toList(growable: false);
