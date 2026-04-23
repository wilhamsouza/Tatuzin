class AdminCrmCustomersQuery {
  const AdminCrmCustomersQuery({
    required this.companyId,
    this.page = 1,
    this.pageSize = 20,
    this.search,
    this.tag,
    this.sortBy = 'updatedAt',
    this.sortDirection = 'desc',
  });

  final String companyId;
  final int page;
  final int pageSize;
  final String? search;
  final String? tag;
  final String sortBy;
  final String sortDirection;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'companyId': companyId,
      'page': '$page',
      'pageSize': '$pageSize',
      if (_normalized(search) case final value?) 'search': value,
      if (_normalized(tag) case final value?) 'tag': value,
      'sortBy': sortBy,
      'sortDirection': sortDirection,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminCrmCustomersQuery &&
        other.companyId == companyId &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.tag == tag &&
        other.sortBy == sortBy &&
        other.sortDirection == sortDirection;
  }

  @override
  int get hashCode => Object.hash(
    companyId,
    page,
    pageSize,
    search,
    tag,
    sortBy,
    sortDirection,
  );
}

class AdminCrmCustomerKey {
  const AdminCrmCustomerKey({
    required this.companyId,
    required this.customerId,
  });

  final String companyId;
  final String customerId;

  Map<String, String> toQueryParameters() {
    return <String, String>{'companyId': companyId};
  }

  @override
  bool operator ==(Object other) {
    return other is AdminCrmCustomerKey &&
        other.companyId == companyId &&
        other.customerId == customerId;
  }

  @override
  int get hashCode => Object.hash(companyId, customerId);
}

class AdminCrmCustomerTimelineQuery {
  const AdminCrmCustomerTimelineQuery({
    required this.companyId,
    required this.customerId,
    this.page = 1,
    this.pageSize = 30,
  });

  final String companyId;
  final String customerId;
  final int page;
  final int pageSize;

  Map<String, String> toQueryParameters() {
    return <String, String>{
      'companyId': companyId,
      'page': '$page',
      'pageSize': '$pageSize',
    };
  }

  @override
  bool operator ==(Object other) {
    return other is AdminCrmCustomerTimelineQuery &&
        other.companyId == companyId &&
        other.customerId == customerId &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(companyId, customerId, page, pageSize);
}

class AdminCrmCommercialSummary {
  const AdminCrmCommercialSummary({
    required this.totalSalesCount,
    required this.totalRevenueCents,
    required this.totalProfitCents,
    required this.totalFiadoPaymentsCents,
    required this.openTasksCount,
    required this.overdueTasksCount,
    required this.lastSaleAt,
    required this.lastFiadoPaymentAt,
    required this.lastCrmEventAt,
  });

  final int totalSalesCount;
  final int totalRevenueCents;
  final int totalProfitCents;
  final int totalFiadoPaymentsCents;
  final int openTasksCount;
  final int overdueTasksCount;
  final DateTime? lastSaleAt;
  final DateTime? lastFiadoPaymentAt;
  final DateTime? lastCrmEventAt;

  factory AdminCrmCommercialSummary.fromMap(Map<String, dynamic> map) {
    return AdminCrmCommercialSummary(
      totalSalesCount: _readOptionalInt(map, 'totalSalesCount') ?? 0,
      totalRevenueCents: _readOptionalInt(map, 'totalRevenueCents') ?? 0,
      totalProfitCents: _readOptionalInt(map, 'totalProfitCents') ?? 0,
      totalFiadoPaymentsCents:
          _readOptionalInt(map, 'totalFiadoPaymentsCents') ?? 0,
      openTasksCount: _readOptionalInt(map, 'openTasksCount') ?? 0,
      overdueTasksCount: _readOptionalInt(map, 'overdueTasksCount') ?? 0,
      lastSaleAt: _readOptionalDateTime(map, 'lastSaleAt'),
      lastFiadoPaymentAt: _readOptionalDateTime(map, 'lastFiadoPaymentAt'),
      lastCrmEventAt: _readOptionalDateTime(map, 'lastCrmEventAt'),
    );
  }
}

class AdminCrmTag {
  const AdminCrmTag({
    required this.id,
    required this.assignmentId,
    required this.label,
    required this.color,
    required this.assignedAt,
  });

  final String id;
  final String assignmentId;
  final String label;
  final String? color;
  final DateTime? assignedAt;

  factory AdminCrmTag.fromMap(Map<String, dynamic> map) {
    return AdminCrmTag(
      id: _readString(map, 'id'),
      assignmentId: _readString(map, 'assignmentId'),
      label: _readString(map, 'label'),
      color: _readOptionalString(map, 'color'),
      assignedAt: _readOptionalDateTime(map, 'assignedAt'),
    );
  }
}

class AdminCrmCustomerSummary {
  const AdminCrmCustomerSummary({
    required this.id,
    required this.companyId,
    required this.localUuid,
    required this.name,
    required this.phone,
    required this.address,
    required this.operationalNotes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    required this.commercialSummary,
  });

  final String id;
  final String companyId;
  final String localUuid;
  final String name;
  final String? phone;
  final String? address;
  final String? operationalNotes;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<AdminCrmTag> tags;
  final AdminCrmCommercialSummary commercialSummary;

  factory AdminCrmCustomerSummary.fromMap(Map<String, dynamic> map) {
    return AdminCrmCustomerSummary(
      id: _readString(map, 'id'),
      companyId: _readString(map, 'companyId'),
      localUuid: _readString(map, 'localUuid'),
      name: _readString(map, 'name'),
      phone: _readOptionalString(map, 'phone'),
      address: _readOptionalString(map, 'address'),
      operationalNotes: _readOptionalString(map, 'operationalNotes'),
      isActive: map['isActive'] == true,
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      tags: _readItemMaps(map, 'tags').map(AdminCrmTag.fromMap).toList(),
      commercialSummary: AdminCrmCommercialSummary.fromMap(
        _readMap(map, 'commercialSummary'),
      ),
    );
  }
}

class AdminCrmActor {
  const AdminCrmActor({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory AdminCrmActor.fromMap(Map<String, dynamic> map) {
    return AdminCrmActor(
      id: _readString(map, 'id'),
      name: _readString(map, 'name'),
      email: _readString(map, 'email'),
    );
  }
}

class AdminCrmNote {
  const AdminCrmNote({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.author,
  });

  final String id;
  final String body;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final AdminCrmActor? author;

  factory AdminCrmNote.fromMap(Map<String, dynamic> map) {
    return AdminCrmNote(
      id: _readString(map, 'id'),
      body: _readString(map, 'body'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      author: map['author'] is Map<String, dynamic>
          ? AdminCrmActor.fromMap(map['author'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AdminCrmTask {
  const AdminCrmTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.dueAt,
    required this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.assignedTo,
  });

  final String id;
  final String title;
  final String? description;
  final String status;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final AdminCrmActor? createdBy;
  final AdminCrmActor? assignedTo;

  factory AdminCrmTask.fromMap(Map<String, dynamic> map) {
    return AdminCrmTask(
      id: _readString(map, 'id'),
      title: _readString(map, 'title'),
      description: _readOptionalString(map, 'description'),
      status: _readString(map, 'status'),
      dueAt: _readOptionalDateTime(map, 'dueAt'),
      completedAt: _readOptionalDateTime(map, 'completedAt'),
      createdAt: _readOptionalDateTime(map, 'createdAt'),
      updatedAt: _readOptionalDateTime(map, 'updatedAt'),
      createdBy: map['createdBy'] is Map<String, dynamic>
          ? AdminCrmActor.fromMap(map['createdBy'] as Map<String, dynamic>)
          : null,
      assignedTo: map['assignedTo'] is Map<String, dynamic>
          ? AdminCrmActor.fromMap(map['assignedTo'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AdminCrmCustomerDetail {
  const AdminCrmCustomerDetail({
    required this.customer,
    required this.notes,
    required this.tasks,
  });

  final AdminCrmCustomerSummary customer;
  final List<AdminCrmNote> notes;
  final List<AdminCrmTask> tasks;

  factory AdminCrmCustomerDetail.fromMap(Map<String, dynamic> map) {
    return AdminCrmCustomerDetail(
      customer: AdminCrmCustomerSummary.fromMap(_readMap(map, 'customer')),
      notes: _readItemMaps(map, 'notes').map(AdminCrmNote.fromMap).toList(),
      tasks: _readItemMaps(map, 'tasks').map(AdminCrmTask.fromMap).toList(),
    );
  }
}

class AdminCrmTimelineEvent {
  const AdminCrmTimelineEvent({
    required this.id,
    required this.source,
    required this.eventType,
    required this.occurredAt,
    required this.headline,
    required this.body,
    required this.actor,
    required this.amountCents,
    required this.metadata,
  });

  final String id;
  final String source;
  final String eventType;
  final DateTime? occurredAt;
  final String headline;
  final String? body;
  final AdminCrmActor? actor;
  final int? amountCents;
  final Map<String, dynamic>? metadata;

  factory AdminCrmTimelineEvent.fromMap(Map<String, dynamic> map) {
    return AdminCrmTimelineEvent(
      id: _readString(map, 'id'),
      source: _readString(map, 'source'),
      eventType: _readString(map, 'eventType'),
      occurredAt: _readOptionalDateTime(map, 'occurredAt'),
      headline: _readString(map, 'headline'),
      body: _readOptionalString(map, 'body'),
      actor: map['actor'] is Map<String, dynamic>
          ? AdminCrmActor.fromMap(map['actor'] as Map<String, dynamic>)
          : null,
      amountCents: _readOptionalInt(map, 'amountCents'),
      metadata: map['metadata'] is Map<String, dynamic>
          ? map['metadata'] as Map<String, dynamic>
          : null,
    );
  }
}

String? _normalized(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, dynamic> _readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('Campo "$key" ausente no payload de CRM.');
}

List<Map<String, dynamic>> _readItemMaps(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List<dynamic>) {
    return const <Map<String, dynamic>>[];
  }
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

String _readString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('Campo "$key" ausente no payload de CRM.');
}

String? _readOptionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

int? _readOptionalInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String && value.trim().isNotEmpty) {
    return int.tryParse(value.trim());
  }
  return null;
}

DateTime? _readOptionalDateTime(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}
