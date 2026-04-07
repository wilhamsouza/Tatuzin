class BackupFileInfo {
  const BackupFileInfo({
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
    required this.createdAt,
    required this.isSafetyCopy,
  });

  final String filePath;
  final String fileName;
  final int sizeBytes;
  final DateTime createdAt;
  final bool isSafetyCopy;
}
