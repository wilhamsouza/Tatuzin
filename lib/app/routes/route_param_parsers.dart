import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_async_value_view.dart';

String? parseStringParam(GoRouterState state, String name) {
  final value = state.pathParameters[name]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

String? parseOptionalStringQueryParam(GoRouterState state, String name) {
  final value = state.uri.queryParameters[name]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

int? parseIntParam(GoRouterState state, String name) {
  final value = parseStringParam(state, name);
  if (value == null) {
    return null;
  }
  return int.tryParse(value);
}

int? parseOptionalIntParam(GoRouterState state, String name) {
  final value = parseStringParam(state, name);
  if (value == null) {
    return null;
  }
  return int.tryParse(value);
}

DateTime? parseDateParam(GoRouterState state, String name) {
  final value = parseStringParam(state, name);
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value);
}

T? routeExtraAs<T>(GoRouterState state) {
  final extra = state.extra;
  return extra is T ? extra : null;
}

Widget invalidRoutePage({
  String title = 'Rota invalida',
  String message =
      'Nao foi possivel abrir esta tela. Verifique o link e tente novamente.',
  String? detailsMessage,
}) {
  return AppAsyncValueView.error(
    title: title,
    message: message,
    detailsMessage: detailsMessage,
  );
}

Widget invalidParamPage(String paramName) {
  return invalidRoutePage(
    message: 'O parametro "$paramName" desta rota esta invalido.',
  );
}

Widget buildIntParamRoute(
  GoRouterState state,
  String paramName,
  Widget Function(int value) builder,
) {
  final value = parseIntParam(state, paramName);
  if (value == null) {
    return invalidParamPage(paramName);
  }
  return builder(value);
}

Widget buildTwoIntParamRoute(
  GoRouterState state,
  String firstParamName,
  String secondParamName,
  Widget Function(int firstValue, int secondValue) builder,
) {
  final firstValue = parseIntParam(state, firstParamName);
  if (firstValue == null) {
    return invalidParamPage(firstParamName);
  }

  final secondValue = parseIntParam(state, secondParamName);
  if (secondValue == null) {
    return invalidParamPage(secondParamName);
  }

  return builder(firstValue, secondValue);
}
