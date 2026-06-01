import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'admin_surface.dart';

class AdminRouteErrorPage extends StatelessWidget {
  const AdminRouteErrorPage({super.key, required this.location, this.message});

  final String location;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      title: 'Rota invalida',
      subtitle:
          'Nao encontramos uma tela do Admin Web para este endereco. A navegacao principal continua disponivel.',
      trailing: FilledButton.tonalIcon(
        onPressed: () => context.go('/dashboard'),
        icon: const Icon(Icons.space_dashboard_rounded),
        label: const Text('Ir para dashboard'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText('Rota solicitada: $location'),
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Detalhe: ${message!.trim()}'),
          ],
          const SizedBox(height: 14),
          const Text(
            'Se voce chegou aqui por um link salvo, procure a empresa pela listagem e abra a Central de suporte.',
          ),
        ],
      ),
    );
  }
}
