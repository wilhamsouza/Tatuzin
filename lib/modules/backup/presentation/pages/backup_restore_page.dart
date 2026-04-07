import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/core/formatters/app_formatters.dart';
import '../../../../app/core/widgets/app_main_drawer.dart';
import '../../../../app/core/widgets/app_page_header.dart';
import '../../../../app/core/widgets/app_section_card.dart';
import '../../../../app/routes/route_names.dart';
import '../../domain/entities/backup_file_info.dart';
import '../../domain/entities/backup_validation_result.dart';
import '../providers/backup_providers.dart';

class BackupRestorePage extends ConsumerWidget {
  const BackupRestorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(backupActionControllerProvider);
    final lastBackup = ref.watch(lastGeneratedBackupProvider);
    final restoreCandidate = ref.watch(selectedRestoreCandidateProvider);
    final isBusy = actionState.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup e restauração')),
      drawer: const AppMainDrawer(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const AppPageHeader(
            title: 'Backup e restaura\u00e7\u00e3o',
            subtitle:
                'Proteja a base local e restaure dados com uma experi\u00eancia mais clara e segura.',
            badgeLabel: 'Prote\u00e7\u00e3o local de dados',
            badgeIcon: Icons.shield_outlined,
            emphasized: true,
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Fazer backup',
            subtitle:
                'Gera um arquivo reutilizavel da base local atual sem alterar o banco em uso.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: isBusy ? null : () => _createBackup(context, ref),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(isBusy ? 'Processando...' : 'Fazer backup'),
                ),
                if (lastBackup != null) ...[
                  const SizedBox(height: 16),
                  _BackupInfoCard(
                    title: lastBackup.isSafetyCopy
                        ? 'Backup de seguranca'
                        : 'Ultimo backup gerado',
                    backupFile: lastBackup,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => _shareBackup(context, ref, lastBackup),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Compartilhar arquivo'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'Restaurar backup',
            subtitle:
                'Escolha um arquivo valido do sistema. Os dados atuais serao substituidos somente apos confirmacao.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () => _selectRestoreCandidate(context, ref),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Selecionar backup'),
                ),
                if (restoreCandidate != null) ...[
                  const SizedBox(height: 16),
                  _RestoreCandidateCard(candidate: restoreCandidate),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: isBusy
                            ? null
                            : () => _confirmAndRestore(context, ref),
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Restaurar agora'),
                      ),
                      TextButton(
                        onPressed: isBusy
                            ? null
                            : () => ref
                                  .read(backupActionControllerProvider.notifier)
                                  .clearRestoreCandidate(),
                        child: const Text('Cancelar selecao'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (actionState.hasError) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  actionState.error.toString(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
    try {
      final backup = await ref
          .read(backupActionControllerProvider.notifier)
          .createManualBackup();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup realizado com sucesso em ${backup.fileName}.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _shareBackup(
    BuildContext context,
    WidgetRef ref,
    BackupFileInfo backupFile,
  ) async {
    try {
      await ref
          .read(backupActionControllerProvider.notifier)
          .shareBackup(backupFile);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arquivo de backup compartilhado com sucesso.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _selectRestoreCandidate(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final candidate = await ref
          .read(backupActionControllerProvider.notifier)
          .pickRestoreCandidate();
      if (candidate == null || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup validado com sucesso: ${candidate.fileName}.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<void> _confirmAndRestore(BuildContext context, WidgetRef ref) async {
    final confirmed = await _showRestoreConfirmation(context);
    if (confirmed != true) {
      return;
    }

    try {
      final result = await ref
          .read(backupActionControllerProvider.notifier)
          .restoreSelectedBackup();
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restauracao concluida com sucesso. Backup de seguranca criado em ${result.safetyBackup.fileName}.',
          ),
        ),
      );
      context.goNamed(AppRouteNames.dashboard);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
    }
  }

  Future<bool?> _showRestoreConfirmation(BuildContext context) async {
    var acknowledged = false;
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirmar restauracao'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A restauracao substituira os dados atuais do aplicativo pela base do backup selecionado.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Antes de sobrescrever, o sistema criara um backup de seguranca da base atual.',
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: acknowledged,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Entendi que os dados atuais serao substituidos.',
                    ),
                    onChanged: (value) {
                      setState(() => acknowledged = value ?? false);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: acknowledged
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('Restaurar backup'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _BackupInfoCard extends StatelessWidget {
  const _BackupInfoCard({required this.title, required this.backupFile});

  final String title;
  final BackupFileInfo backupFile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Text('Arquivo: ${backupFile.fileName}'),
            Text('Tamanho: ${_formatFileSize(backupFile.sizeBytes)}'),
            Text(
              'Gerado em: ${AppFormatters.shortDateTime(backupFile.createdAt)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreCandidateCard extends StatelessWidget {
  const _RestoreCandidateCard({required this.candidate});

  final BackupValidationResult candidate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backup validado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text('Arquivo: ${candidate.fileName}'),
            Text('Tamanho: ${_formatFileSize(candidate.sizeBytes)}'),
            Text('Schema: v${candidate.schemaVersion}'),
            Text('Tabelas detectadas: ${candidate.detectedTables.length}'),
          ],
        ),
      ),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
