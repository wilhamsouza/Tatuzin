import '../../../app/core/database/app_database.dart';
import '../../../app/core/database/table_names.dart';
import '../../../app/core/utils/id_generator.dart';
import '../domain/entities/base_product.dart';
import '../domain/entities/modifier_group.dart';
import '../domain/entities/modifier_option.dart';
import '../domain/entities/variant_attribute.dart';
import '../domain/repositories/local_catalog_repository.dart';

class SqliteLocalCatalogRepository implements LocalCatalogRepository {
  const SqliteLocalCatalogRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<BaseProduct>> listBaseProducts({String query = ''}) async {
    final database = await _appDatabase.database;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      final rows = await database.query(
        TableNames.produtosBase,
        orderBy: 'nome COLLATE NOCASE ASC, id ASC',
      );
      return rows.map(_mapBaseProduct).toList();
    }

    final rows = await database.query(
      TableNames.produtosBase,
      where: 'nome LIKE ? COLLATE NOCASE',
      whereArgs: ['%$trimmed%'],
      orderBy: 'nome COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_mapBaseProduct).toList();
  }

  @override
  Future<BaseProduct?> findBaseProductById(int id) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.produtosBase,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapBaseProduct(rows.first);
  }

  @override
  Future<List<int>> listVariantProductIdsForBase(int baseProductId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.produtosBaseVariantes,
      columns: const ['produto_id'],
      where: 'produto_base_id = ?',
      whereArgs: [baseProductId],
      orderBy: 'produto_id ASC',
    );
    return rows
        .map((row) => row['produto_id'])
        .whereType<int>()
        .toList(growable: false);
  }

  @override
  Future<List<VariantAttribute>> listVariantAttributes(int productId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.produtoVarianteAtributos,
      where: 'produto_id = ?',
      whereArgs: [productId],
      orderBy: 'chave COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_mapVariantAttribute).toList();
  }

  @override
  Future<List<ModifierGroup>> listModifierGroups(int baseProductId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.gruposModificadores,
      where: 'produto_base_id = ?',
      whereArgs: [baseProductId],
      orderBy: 'nome COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_mapModifierGroup).toList();
  }

  @override
  Future<List<ModifierOption>> listModifierOptions(int groupId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      TableNames.opcoesModificadores,
      where: 'grupo_modificador_id = ?',
      whereArgs: [groupId],
      orderBy: 'ordem ASC, nome COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_mapModifierOption).toList();
  }

  @override
  Future<int> upsertModifierGroup({
    int? id,
    required ModifierGroupInput input,
  }) async {
    final database = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    if (id == null) {
      return database.insert(TableNames.gruposModificadores, {
        'uuid': IdGenerator.next(),
        'produto_base_id': input.baseProductId,
        'nome': input.name.trim(),
        'obrigatorio': input.isRequired ? 1 : 0,
        'min_selecoes': input.minSelections,
        'max_selecoes': input.maxSelections,
        'ativo': input.isActive ? 1 : 0,
        'criado_em': now,
        'atualizado_em': now,
      });
    }

    await database.update(
      TableNames.gruposModificadores,
      {
        'produto_base_id': input.baseProductId,
        'nome': input.name.trim(),
        'obrigatorio': input.isRequired ? 1 : 0,
        'min_selecoes': input.minSelections,
        'max_selecoes': input.maxSelections,
        'ativo': input.isActive ? 1 : 0,
        'atualizado_em': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return id;
  }

  @override
  Future<int> upsertModifierOption({
    int? id,
    required ModifierOptionInput input,
  }) async {
    final database = await _appDatabase.database;
    final now = DateTime.now().toIso8601String();
    if (id == null) {
      return database.insert(TableNames.opcoesModificadores, {
        'uuid': IdGenerator.next(),
        'grupo_modificador_id': input.groupId,
        'nome': input.name.trim(),
        'tipo_ajuste': input.adjustmentType,
        'preco_delta_centavos': input.priceDeltaCents,
        'linked_produto_id': input.linkedProductId,
        'ativo': input.isActive ? 1 : 0,
        'ordem': input.sortOrder,
        'criado_em': now,
        'atualizado_em': now,
      });
    }

    await database.update(
      TableNames.opcoesModificadores,
      {
        'grupo_modificador_id': input.groupId,
        'nome': input.name.trim(),
        'tipo_ajuste': input.adjustmentType,
        'preco_delta_centavos': input.priceDeltaCents,
        'linked_produto_id': input.linkedProductId,
        'ativo': input.isActive ? 1 : 0,
        'ordem': input.sortOrder,
        'atualizado_em': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return id;
  }

  BaseProduct _mapBaseProduct(Map<String, Object?> row) {
    return BaseProduct(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      name: row['nome'] as String,
      description: row['descricao'] as String?,
      categoryId: row['categoria_id'] as int?,
      isActive: (row['ativo'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }

  VariantAttribute _mapVariantAttribute(Map<String, Object?> row) {
    return VariantAttribute(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      productId: row['produto_id'] as int,
      key: row['chave'] as String,
      value: row['valor'] as String,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }

  ModifierGroup _mapModifierGroup(Map<String, Object?> row) {
    return ModifierGroup(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      baseProductId: row['produto_base_id'] as int,
      name: row['nome'] as String,
      isRequired: (row['obrigatorio'] as int? ?? 0) == 1,
      minSelections: row['min_selecoes'] as int? ?? 0,
      maxSelections: row['max_selecoes'] as int?,
      isActive: (row['ativo'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }

  ModifierOption _mapModifierOption(Map<String, Object?> row) {
    return ModifierOption(
      id: row['id'] as int,
      uuid: row['uuid'] as String,
      groupId: row['grupo_modificador_id'] as int,
      name: row['nome'] as String,
      adjustmentType: row['tipo_ajuste'] as String,
      priceDeltaCents: row['preco_delta_centavos'] as int? ?? 0,
      linkedProductId: row['linked_produto_id'] as int?,
      sortOrder: row['ordem'] as int? ?? 0,
      isActive: (row['ativo'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(row['criado_em'] as String),
      updatedAt: DateTime.parse(row['atualizado_em'] as String),
    );
  }
}
