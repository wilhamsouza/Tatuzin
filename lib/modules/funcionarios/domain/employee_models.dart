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
      createdAt: _tryParseDate(source['createdAt']),
      updatedAt: _tryParseDate(source['updatedAt']),
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

String? _readString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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
