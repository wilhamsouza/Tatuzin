import '../../domain/entities/supplier.dart';
import '../../../../app/core/sync/sync_status.dart';

class SupplierModel extends Supplier {
  const SupplierModel({
    required super.id,
    required super.uuid,
    required super.name,
    required super.tradeName,
    required super.phone,
    required super.email,
    required super.address,
    required super.document,
    required super.contactPerson,
    required super.notes,
    required super.isActive,
    required super.createdAt,
    required super.updatedAt,
    required super.deletedAt,
    super.remoteId,
    super.syncStatus,
    super.lastSyncedAt,
    super.pendingPurchasesCount,
    super.pendingAmountCents,
  });

  factory SupplierModel.fromMap(Map<String, Object?> map) {
    return SupplierModel(
      id: map['id'] as int,
      uuid: map['uuid'] as String,
      name: map['nome'] as String,
      tradeName: map['nome_fantasia'] as String?,
      phone: map['telefone'] as String?,
      email: map['email'] as String?,
      address: map['endereco'] as String?,
      document: map['documento'] as String?,
      contactPerson: map['contato_responsavel'] as String?,
      notes: map['observacao'] as String?,
      isActive: (map['ativo'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['criado_em'] as String),
      updatedAt: DateTime.parse(map['atualizado_em'] as String),
      deletedAt: map['deletado_em'] == null
          ? null
          : DateTime.parse(map['deletado_em'] as String),
      remoteId: map['sync_remote_id'] as String?,
      syncStatus: syncStatusFromStorage(map['sync_status'] as String?),
      lastSyncedAt: map['sync_last_synced_at'] == null
          ? null
          : DateTime.parse(map['sync_last_synced_at'] as String),
      pendingPurchasesCount:
          map['pendencia_quantidade'] as int? ??
          map['pending_purchases_count'] as int? ??
          0,
      pendingAmountCents:
          map['pendencia_centavos'] as int? ??
          map['pending_amount_cents'] as int? ??
          0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'nome': name,
      'nome_fantasia': tradeName,
      'telefone': phone,
      'email': email,
      'endereco': address,
      'documento': document,
      'contato_responsavel': contactPerson,
      'observacao': notes,
      'ativo': isActive ? 1 : 0,
      'criado_em': createdAt.toIso8601String(),
      'atualizado_em': updatedAt.toIso8601String(),
      'deletado_em': deletedAt?.toIso8601String(),
      'sync_remote_id': remoteId,
      'sync_status': syncStatus?.storageValue,
      'sync_last_synced_at': lastSyncedAt?.toIso8601String(),
    };
  }

  SupplierModel copyWith({
    int? id,
    String? uuid,
    String? name,
    String? tradeName,
    String? phone,
    String? email,
    String? address,
    String? document,
    String? contactPerson,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? remoteId,
    SyncStatus? syncStatus,
    DateTime? lastSyncedAt,
    int? pendingPurchasesCount,
    int? pendingAmountCents,
  }) {
    return SupplierModel(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      tradeName: tradeName ?? this.tradeName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      document: document ?? this.document,
      contactPerson: contactPerson ?? this.contactPerson,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      remoteId: remoteId ?? this.remoteId,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pendingPurchasesCount:
          pendingPurchasesCount ?? this.pendingPurchasesCount,
      pendingAmountCents: pendingAmountCents ?? this.pendingAmountCents,
    );
  }
}
