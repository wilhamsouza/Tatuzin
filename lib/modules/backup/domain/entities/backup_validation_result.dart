class BackupValidationResult {
  const BackupValidationResult({
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
    required this.schemaVersion,
    required this.detectedTables,
  });

  final String filePath;
  final String fileName;
  final int sizeBytes;
  final int schemaVersion;
  final List<String> detectedTables;
}
