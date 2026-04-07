import '../../domain/entities/category.dart';

class RemoteCategoryRecord {
  const RemoteCategoryRecord({
    required this.remoteId,
    required this.localUuid,
    required this.name,
    required this.description,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory RemoteCategoryRecord.fromJson(Map<String, dynamic> json) {
    final remoteId = json['id'] as String;
    return RemoteCategoryRecord(
      remoteId: remoteId,
      localUuid: (json['localUuid'] as String?)?.trim().isNotEmpty == true
          ? json['localUuid'] as String
          : remoteId,
      name: json['name'] as String,
      description: json['description'] as String?,
      isActive: (json['isActive'] as bool?) ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
    );
  }

  factory RemoteCategoryRecord.fromLocalCategory(Category category) {
    return RemoteCategoryRecord(
      remoteId: category.remoteId ?? '',
      localUuid: category.uuid,
      name: category.name,
      description: category.description,
      isActive: category.isActive,
      createdAt: category.createdAt,
      updatedAt: category.updatedAt,
      deletedAt: category.deletedAt,
    );
  }

  final String remoteId;
  final String localUuid;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, dynamic> toUpsertBody() {
    return <String, dynamic>{
      'localUuid': localUuid,
      'name': name,
      'description': description,
      'isActive': isActive,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}
