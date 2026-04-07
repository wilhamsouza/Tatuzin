import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/app/admin_web_app.dart';

void main() {
  usePathUrlStrategy();
  runApp(const ProviderScope(child: AdminWebApp()));
}
