import 'package:flutter/material.dart';

import '../../../../app/core/theme/app_design_tokens.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';

class EmployeesPage extends StatelessWidget {
  const EmployeesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Funcionários')),
      drawer: const AppMainDrawer(),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(layout.space8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Funcionários',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: layout.space4),
              Text(
                'Em breve: cadastre vendedores, caixas e gerentes com permissões.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
