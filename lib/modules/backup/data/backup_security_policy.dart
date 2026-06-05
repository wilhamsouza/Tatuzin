import 'package:flutter/foundation.dart';

class BackupSecurityPolicy {
  const BackupSecurityPolicy({bool isReleaseMode = kReleaseMode})
    : _isReleaseMode = isReleaseMode;

  final bool _isReleaseMode;

  static const rawDatabaseBlockedReason =
      'Backup local bruto esta indisponivel nesta versao por seguranca. '
      'Em breve havera backup criptografado.';

  bool get canExportRawDatabase => !_isReleaseMode;

  bool get canShareRawDatabase => !_isReleaseMode;

  bool get canImportRawDatabase => !_isReleaseMode;

  bool get shouldWarnAboutRawDatabase => !_isReleaseMode;
}
