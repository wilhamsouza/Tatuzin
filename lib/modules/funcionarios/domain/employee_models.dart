enum EmployeeRole {
  owner('OWNER', 'Dono'),
  manager('MANAGER', 'Gerente'),
  cashier('CASHIER', 'Caixa'),
  seller('SELLER', 'Vendedor'),
  stockOperator('STOCK_OPERATOR', 'Estoque'),
  readOnly('READ_ONLY', 'Leitura'),
  unknown('UNKNOWN', 'Cargo desconhecido');

  const EmployeeRole(this.key, this.label);

  final String key;
  final String label;

  bool get isOwner => this == EmployeeRole.owner;

  static EmployeeRole fromKey(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    return EmployeeRole.values.firstWhere(
      (role) => role.key == normalized,
      orElse: () => EmployeeRole.unknown,
    );
  }

  static List<EmployeeRole> get editableRoles => const <EmployeeRole>[
    EmployeeRole.manager,
    EmployeeRole.cashier,
    EmployeeRole.seller,
    EmployeeRole.stockOperator,
    EmployeeRole.readOnly,
  ];
}

enum EmployeeStatus {
  active('ACTIVE', 'Ativo'),
  invited('INVITED', 'Convidado'),
  disabled('DISABLED', 'Desativado'),
  unknown('UNKNOWN', 'Status desconhecido');

  const EmployeeStatus(this.key, this.label);

  final String key;
  final String label;

  bool get isDisabled => this == EmployeeStatus.disabled;

  static EmployeeStatus fromKey(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    return EmployeeStatus.values.firstWhere(
      (status) => status.key == normalized,
      orElse: () => EmployeeStatus.unknown,
    );
  }

  static List<EmployeeStatus> get editableStatuses => const <EmployeeStatus>[
    EmployeeStatus.active,
    EmployeeStatus.invited,
    EmployeeStatus.disabled,
  ];
}

enum EmployeeAccessStatus {
  noAccess('NO_ACCESS', 'Sem acesso'),
  temporaryPasswordPending(
    'TEMPORARY_PASSWORD_PENDING',
    'Senha temporária pendente',
  ),
  active('ACTIVE', 'Acesso ativo'),
  disabled('DISABLED', 'Desativado'),
  unknown('UNKNOWN', 'Acesso desconhecido');

  const EmployeeAccessStatus(this.key, this.label);

  final String key;
  final String label;

  static EmployeeAccessStatus fromKey(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    return EmployeeAccessStatus.values.firstWhere(
      (status) => status.key == normalized,
      orElse: () => EmployeeAccessStatus.unknown,
    );
  }
}

enum EmployeePermission {
  salesCreate('sales.create', 'Criar vendas', 'Vendas'),
  salesCancel('sales.cancel', 'Cancelar vendas', 'Vendas'),
  salesDiscount('sales.discount', 'Dar desconto', 'Vendas'),
  cashOpen('cash.open', 'Abrir caixa', 'Caixa'),
  cashClose('cash.close', 'Fechar caixa', 'Caixa'),
  cashWithdraw('cash.withdraw', 'Sangria', 'Caixa'),
  productsRead('products.read', 'Ver produtos', 'Produtos e estoque'),
  productsWrite('products.write', 'Editar produtos', 'Produtos e estoque'),
  stockAdjust('stock.adjust', 'Ajustar estoque', 'Produtos e estoque'),
  customersRead('customers.read', 'Ver clientes', 'Clientes e fiado'),
  customersWrite('customers.write', 'Editar clientes', 'Clientes e fiado'),
  fiadoRead('fiado.read', 'Ver fiado', 'Clientes e fiado'),
  fiadoReceive('fiado.receive', 'Receber fiado', 'Clientes e fiado'),
  reportsBasic('reports.basic', 'Relatórios básicos', 'Relatórios'),
  reportsAdvanced('reports.advanced', 'Relatórios avançados', 'Relatórios'),
  employeesManage(
    'employees.manage',
    'Gerenciar funcionários',
    'Administração',
  ),
  devicesManage('devices.manage', 'Gerenciar dispositivos', 'Administração'),
  subscriptionManage(
    'subscription.manage',
    'Gerenciar assinatura',
    'Administração',
  );

  const EmployeePermission(this.key, this.label, this.group);

  final String key;
  final String label;
  final String group;

  static EmployeePermission? tryFromKey(Object? value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final permission in EmployeePermission.values) {
      if (permission.key == normalized) {
        return permission;
      }
    }
    return null;
  }

  static Set<EmployeePermission> parseList(Object? value) {
    if (value is! Iterable) {
      return const <EmployeePermission>{};
    }
    return value
        .map(EmployeePermission.tryFromKey)
        .whereType<EmployeePermission>()
        .toSet();
  }
}

Set<EmployeePermission> defaultPermissionsForRole(EmployeeRole role) {
  switch (role) {
    case EmployeeRole.manager:
      return {
        EmployeePermission.salesCreate,
        EmployeePermission.salesCancel,
        EmployeePermission.salesDiscount,
        EmployeePermission.cashOpen,
        EmployeePermission.cashClose,
        EmployeePermission.cashWithdraw,
        EmployeePermission.productsRead,
        EmployeePermission.productsWrite,
        EmployeePermission.stockAdjust,
        EmployeePermission.customersRead,
        EmployeePermission.customersWrite,
        EmployeePermission.fiadoRead,
        EmployeePermission.fiadoReceive,
        EmployeePermission.reportsBasic,
        EmployeePermission.reportsAdvanced,
        EmployeePermission.employeesManage,
      };
    case EmployeeRole.cashier:
      return {
        EmployeePermission.salesCreate,
        EmployeePermission.cashOpen,
        EmployeePermission.cashClose,
        EmployeePermission.customersRead,
        EmployeePermission.fiadoRead,
        EmployeePermission.fiadoReceive,
      };
    case EmployeeRole.seller:
      return {
        EmployeePermission.salesCreate,
        EmployeePermission.customersRead,
        EmployeePermission.customersWrite,
      };
    case EmployeeRole.stockOperator:
      return {EmployeePermission.productsRead, EmployeePermission.stockAdjust};
    case EmployeeRole.readOnly:
      return {
        EmployeePermission.productsRead,
        EmployeePermission.customersRead,
        EmployeePermission.fiadoRead,
        EmployeePermission.reportsBasic,
      };
    case EmployeeRole.owner:
      return EmployeePermission.values.toSet();
    case EmployeeRole.unknown:
      return const <EmployeePermission>{};
  }
}

class EmployeeProfile {
  const EmployeeProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.permissions,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.phone,
    this.invitedAt,
    this.inviteExpiresAt,
    this.acceptedAt,
    this.disabledAt,
    this.accessStatus = EmployeeAccessStatus.noAccess,
    this.temporaryPasswordExpiresAt,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final EmployeeRole role;
  final EmployeeStatus status;
  final Set<EmployeePermission> permissions;
  final DateTime? invitedAt;
  final DateTime? inviteExpiresAt;
  final DateTime? acceptedAt;
  final DateTime? disabledAt;
  final EmployeeAccessStatus accessStatus;
  final DateTime? temporaryPasswordExpiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOwner => role.isOwner;

  bool get isDisabled => status == EmployeeStatus.disabled;

  factory EmployeeProfile.fromMap(Map<String, dynamic> source) {
    return EmployeeProfile(
      id: _readString(source['id']) ?? '',
      name: _readString(source['name']) ?? 'Funcionário sem nome',
      email: _readString(source['email']),
      phone: _readString(source['phone']),
      role: EmployeeRole.fromKey(source['role']),
      status: EmployeeStatus.fromKey(source['status']),
      permissions: EmployeePermission.parseList(source['permissions']),
      invitedAt: _tryParseDate(source['invitedAt']),
      inviteExpiresAt: _tryParseDate(source['inviteExpiresAt']),
      acceptedAt: _tryParseDate(source['acceptedAt']),
      disabledAt: _tryParseDate(source['disabledAt']),
      accessStatus: EmployeeAccessStatus.fromKey(source['accessStatus']),
      temporaryPasswordExpiresAt: _tryParseDate(
        source['temporaryPasswordExpiresAt'],
      ),
      createdAt: _tryParseDate(source['createdAt']),
      updatedAt: _tryParseDate(source['updatedAt']),
    );
  }
}

class EmployeeTemporaryPasswordResult {
  const EmployeeTemporaryPasswordResult({
    required this.employee,
    required this.login,
    required this.temporaryPassword,
    required this.temporaryPasswordExpiresAt,
    this.message,
  });

  final EmployeeProfile employee;
  final String login;
  final String temporaryPassword;
  final DateTime? temporaryPasswordExpiresAt;
  final String? message;

  factory EmployeeTemporaryPasswordResult.fromMap(Map<String, dynamic> source) {
    final rawEmployee = source['employee'];
    return EmployeeTemporaryPasswordResult(
      employee: rawEmployee is Map
          ? EmployeeProfile.fromMap(Map<String, dynamic>.from(rawEmployee))
          : EmployeeProfile.fromMap(const <String, dynamic>{}),
      login: _readString(source['login']) ?? '',
      temporaryPassword: _readString(source['temporaryPassword']) ?? '',
      temporaryPasswordExpiresAt: _tryParseDate(
        source['temporaryPasswordExpiresAt'],
      ),
      message: _readString(source['message']),
    );
  }
}

class EmployeesPageResult {
  const EmployeesPageResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.count,
    required this.hasNext,
    required this.hasPrevious,
  });

  final List<EmployeeProfile> items;
  final int page;
  final int pageSize;
  final int total;
  final int count;
  final bool hasNext;
  final bool hasPrevious;

  factory EmployeesPageResult.fromMap(Map<String, dynamic> source) {
    final rawItems = source['items'];
    final items = rawItems is Iterable
        ? rawItems
              .whereType<Map>()
              .map(
                (item) =>
                    EmployeeProfile.fromMap(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false)
        : const <EmployeeProfile>[];
    return EmployeesPageResult(
      items: items,
      page: _readInt(source['page']) ?? 1,
      pageSize: _readInt(source['pageSize']) ?? items.length,
      total: _readInt(source['total']) ?? items.length,
      count: _readInt(source['count']) ?? items.length,
      hasNext: source['hasNext'] == true,
      hasPrevious: source['hasPrevious'] == true,
    );
  }
}

class EmployeeMutationInput {
  const EmployeeMutationInput({
    required this.name,
    required this.role,
    required this.permissions,
    this.email,
    this.phone,
    this.status,
  });

  final String name;
  final String? email;
  final String? phone;
  final EmployeeRole role;
  final EmployeeStatus? status;
  final Set<EmployeePermission>? permissions;

  Map<String, dynamic> toCreateBody() {
    return _toBody(includeStatus: status != null);
  }

  Map<String, dynamic> toUpdateBody() {
    return _toBody(includeStatus: status != null);
  }

  Map<String, dynamic> _toBody({required bool includeStatus}) {
    if (role.isOwner) {
      throw ArgumentError('OWNER não pode ser enviado pelo app.');
    }
    if (role == EmployeeRole.unknown) {
      throw ArgumentError('Cargo inválido para envio.');
    }
    if (includeStatus && status == EmployeeStatus.unknown) {
      throw ArgumentError('Status inválido para envio.');
    }
    return <String, dynamic>{
      'name': name.trim(),
      'email': _nullableTrim(email),
      'phone': _nullableTrim(phone),
      'role': role.key,
      if (includeStatus && status != null) 'status': status!.key,
      if (permissions != null)
        'permissions': permissions!
            .map((permission) => permission.key)
            .toList(),
    };
  }
}

class EmployeeActionResult {
  const EmployeeActionResult({required this.employee, this.message});

  final EmployeeProfile employee;
  final String? message;

  factory EmployeeActionResult.fromMap(Map<String, dynamic> source) {
    final rawEmployee = source['employee'];
    return EmployeeActionResult(
      employee: rawEmployee is Map
          ? EmployeeProfile.fromMap(Map<String, dynamic>.from(rawEmployee))
          : EmployeeProfile.fromMap(const <String, dynamic>{}),
      message: _readString(source['message']),
    );
  }
}

class EmployeeActivityPeriod {
  const EmployeeActivityPeriod({
    required this.label,
    required this.from,
    required this.to,
  });

  final String label;
  final DateTime from;
  final DateTime to;

  String get fromQuery => _dateOnly(from);
  String get toQuery => _dateOnly(to);

  static EmployeeActivityPeriod today({DateTime? now}) {
    final base = _dateAtMidnight(now ?? DateTime.now());
    return EmployeeActivityPeriod(label: 'Hoje', from: base, to: base);
  }

  static EmployeeActivityPeriod yesterday({DateTime? now}) {
    final base = _dateAtMidnight(
      now ?? DateTime.now(),
    ).subtract(const Duration(days: 1));
    return EmployeeActivityPeriod(label: 'Ontem', from: base, to: base);
  }

  static EmployeeActivityPeriod last7Days({DateTime? now}) {
    final end = _dateAtMidnight(now ?? DateTime.now());
    return EmployeeActivityPeriod(
      label: '7 dias',
      from: end.subtract(const Duration(days: 6)),
      to: end,
    );
  }

  static EmployeeActivityPeriod thisMonth({DateTime? now}) {
    final base = _dateAtMidnight(now ?? DateTime.now());
    return EmployeeActivityPeriod(
      label: 'Este mês',
      from: DateTime(base.year, base.month),
      to: base,
    );
  }
}

class EmployeeActivitySummary {
  const EmployeeActivitySummary({
    required this.totalEmployees,
    required this.activeEmployees,
    required this.employeesWithActivity,
    required this.totalSalesCount,
    required this.totalSalesAmountCents,
    required this.totalDiscountAmountCents,
    required this.totalCanceledCount,
    required this.totalStockAdjustments,
    required this.rows,
    required this.tracking,
  });

  final int totalEmployees;
  final int activeEmployees;
  final int employeesWithActivity;
  final int totalSalesCount;
  final int totalSalesAmountCents;
  final int totalDiscountAmountCents;
  final int totalCanceledCount;
  final int totalStockAdjustments;
  final List<EmployeeActivityRow> rows;
  final EmployeeActivityTracking tracking;

  factory EmployeeActivitySummary.fromMap(Map<String, dynamic> source) {
    final rawRows = source['rows'];
    return EmployeeActivitySummary(
      totalEmployees: _readInt(source['totalEmployees']) ?? 0,
      activeEmployees: _readInt(source['activeEmployees']) ?? 0,
      employeesWithActivity: _readInt(source['employeesWithActivity']) ?? 0,
      totalSalesCount: _readInt(source['totalSalesCount']) ?? 0,
      totalSalesAmountCents: _readInt(source['totalSalesAmountCents']) ?? 0,
      totalDiscountAmountCents:
          _readInt(source['totalDiscountAmountCents']) ?? 0,
      totalCanceledCount: _readInt(source['totalCanceledCount']) ?? 0,
      totalStockAdjustments: _readInt(source['totalStockAdjustments']) ?? 0,
      rows: rawRows is Iterable
          ? rawRows
                .whereType<Map>()
                .map(
                  (row) => EmployeeActivityRow.fromMap(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList(growable: false)
          : const <EmployeeActivityRow>[],
      tracking: EmployeeActivityTracking.fromMap(source['tracking']),
    );
  }
}

class EmployeeActivityRow {
  const EmployeeActivityRow({
    required this.employeeId,
    required this.name,
    required this.role,
    required this.status,
    required this.salesCount,
    required this.salesAmountCents,
    required this.discountAmountCents,
    required this.canceledSalesCount,
    required this.stockAdjustmentsCount,
    required this.cashActionsCount,
    required this.lastActivityAt,
  });

  final String employeeId;
  final String name;
  final EmployeeRole role;
  final EmployeeStatus status;
  final int salesCount;
  final int salesAmountCents;
  final int discountAmountCents;
  final int canceledSalesCount;
  final int stockAdjustmentsCount;
  final int cashActionsCount;
  final DateTime? lastActivityAt;

  bool get hasActivity =>
      salesCount > 0 ||
      salesAmountCents > 0 ||
      discountAmountCents > 0 ||
      canceledSalesCount > 0 ||
      stockAdjustmentsCount > 0 ||
      cashActionsCount > 0 ||
      lastActivityAt != null;

  factory EmployeeActivityRow.fromMap(Map<String, dynamic> source) {
    return EmployeeActivityRow(
      employeeId: _readString(source['employeeId']) ?? '',
      name: _readString(source['name']) ?? 'Funcionário sem nome',
      role: EmployeeRole.fromKey(source['role']),
      status: EmployeeStatus.fromKey(source['status']),
      salesCount: _readInt(source['salesCount']) ?? 0,
      salesAmountCents: _readInt(source['salesAmountCents']) ?? 0,
      discountAmountCents: _readInt(source['discountAmountCents']) ?? 0,
      canceledSalesCount: _readInt(source['canceledSalesCount']) ?? 0,
      stockAdjustmentsCount: _readInt(source['stockAdjustmentsCount']) ?? 0,
      cashActionsCount: _readInt(source['cashActionsCount']) ?? 0,
      lastActivityAt: _tryParseDate(source['lastActivityAt']),
    );
  }
}

class EmployeeActivityDetail {
  const EmployeeActivityDetail({
    required this.employee,
    required this.summary,
    required this.timeline,
    required this.tracking,
  });

  final EmployeeActivityEmployee employee;
  final EmployeeActivityRow summary;
  final List<EmployeeActivityTimelineItem> timeline;
  final EmployeeActivityTracking tracking;

  factory EmployeeActivityDetail.fromMap(Map<String, dynamic> source) {
    final rawTimeline = source['timeline'];
    final rawEmployee = source['employee'];
    final rawSummary = source['summary'];
    final employee = rawEmployee is Map
        ? EmployeeActivityEmployee.fromMap(
            Map<String, dynamic>.from(rawEmployee),
          )
        : EmployeeActivityEmployee.fromMap(const <String, dynamic>{});
    return EmployeeActivityDetail(
      employee: employee,
      summary: rawSummary is Map
          ? EmployeeActivityRow.fromMap(<String, dynamic>{
              'employeeId': employee.id,
              'name': employee.name,
              'role': employee.role.key,
              'status': employee.status.key,
              ...Map<String, dynamic>.from(rawSummary),
            })
          : EmployeeActivityRow.fromMap(<String, dynamic>{
              'employeeId': employee.id,
              'name': employee.name,
              'role': employee.role.key,
              'status': employee.status.key,
            }),
      timeline: rawTimeline is Iterable
          ? rawTimeline
                .whereType<Map>()
                .map(
                  (item) => EmployeeActivityTimelineItem.fromMap(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const <EmployeeActivityTimelineItem>[],
      tracking: EmployeeActivityTracking.fromMap(source['tracking']),
    );
  }
}

class EmployeeActivityEmployee {
  const EmployeeActivityEmployee({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
  });

  final String id;
  final String name;
  final EmployeeRole role;
  final EmployeeStatus status;

  factory EmployeeActivityEmployee.fromMap(Map<String, dynamic> source) {
    return EmployeeActivityEmployee(
      id: _readString(source['id']) ?? '',
      name: _readString(source['name']) ?? 'Funcionário sem nome',
      role: EmployeeRole.fromKey(source['role']),
      status: EmployeeStatus.fromKey(source['status']),
    );
  }
}

class EmployeeActivityTimelineItem {
  const EmployeeActivityTimelineItem({
    required this.id,
    required this.occurredAt,
    required this.type,
    required this.title,
    required this.description,
    this.amountCents,
  });

  final String id;
  final DateTime? occurredAt;
  final String type;
  final String title;
  final String description;
  final int? amountCents;

  factory EmployeeActivityTimelineItem.fromMap(Map<String, dynamic> source) {
    return EmployeeActivityTimelineItem(
      id: _readString(source['id']) ?? '',
      occurredAt: _tryParseDate(source['occurredAt']),
      type: _readString(source['type']) ?? 'ACTIVITY',
      title: _readString(source['title']) ?? 'Atividade registrada',
      description: _readString(source['description']) ?? '',
      amountCents: _readInt(source['amountCents']),
    );
  }
}

class EmployeeActivityTracking {
  const EmployeeActivityTracking({required this.partial, required this.notes});

  final bool partial;
  final List<String> notes;

  factory EmployeeActivityTracking.fromMap(Object? source) {
    if (source is! Map) {
      return const EmployeeActivityTracking(partial: false, notes: <String>[]);
    }
    final rawNotes = source['notes'];
    return EmployeeActivityTracking(
      partial: source['partial'] == true,
      notes: rawNotes is Iterable
          ? rawNotes
                .map((note) => note.toString().trim())
                .where((note) => note.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}

String? _readString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime _dateAtMidnight(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _dateOnly(DateTime value) {
  final normalized = _dateAtMidnight(value);
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${normalized.year}-${twoDigits(normalized.month)}-${twoDigits(normalized.day)}';
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

DateTime? _tryParseDate(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value.trim());
}

String? _nullableTrim(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
