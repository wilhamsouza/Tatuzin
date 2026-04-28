import 'package:erp_pdv_app/modules/categorias/domain/entities/category.dart';
import 'package:erp_pdv_app/modules/categorias/domain/repositories/category_repository.dart';
import 'package:erp_pdv_app/modules/categorias/presentation/providers/category_providers.dart';
import 'package:erp_pdv_app/modules/fornecedores/domain/entities/supplier.dart';
import 'package:erp_pdv_app/modules/fornecedores/domain/repositories/supplier_repository.dart';
import 'package:erp_pdv_app/modules/fornecedores/presentation/providers/supplier_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'categoryListProvider e categoryOptionsProvider compartilham carga',
    () async {
      final repository = _CountingCategoryRepository();
      final container = ProviderContainer(
        overrides: [categoryRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final result = await Future.wait([
        container.read(categoryListProvider.future),
        container.read(categoryOptionsProvider.future),
      ]);

      expect(result[0].map((category) => category.name), ['Categoria A']);
      expect(result[1].map((category) => category.name), ['Categoria A']);
      expect(repository.searchCalls, 1);
    },
  );

  test(
    'supplierListProvider e supplierOptionsProvider compartilham carga',
    () async {
      final repository = _CountingSupplierRepository();
      final container = ProviderContainer(
        overrides: [supplierRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final result = await Future.wait([
        container.read(supplierListProvider.future),
        container.read(supplierOptionsProvider.future),
      ]);

      expect(result[0].map((supplier) => supplier.name), ['Fornecedor A']);
      expect(result[1].map((supplier) => supplier.name), ['Fornecedor A']);
      expect(repository.searchCalls, 1);
    },
  );
}

class _CountingCategoryRepository implements CategoryRepository {
  int searchCalls = 0;

  @override
  Future<List<Category>> search({String query = ''}) async {
    searchCalls++;
    return [
      Category(
        id: 1,
        uuid: 'category-1',
        name: 'Categoria A',
        description: null,
        isActive: true,
        createdAt: DateTime(2026, 4, 27),
        updatedAt: DateTime(2026, 4, 27),
        deletedAt: null,
      ),
    ];
  }

  @override
  Future<int> create(CategoryInput input) => throw UnimplementedError();

  @override
  Future<void> update(int id, CategoryInput input) =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) => throw UnimplementedError();
}

class _CountingSupplierRepository implements SupplierRepository {
  int searchCalls = 0;

  @override
  Future<List<Supplier>> search({String query = ''}) async {
    searchCalls++;
    return [
      Supplier(
        id: 1,
        uuid: 'supplier-1',
        name: 'Fornecedor A',
        tradeName: null,
        phone: null,
        email: null,
        address: null,
        document: null,
        contactPerson: null,
        notes: null,
        isActive: true,
        createdAt: DateTime(2026, 4, 27),
        updatedAt: DateTime(2026, 4, 27),
        deletedAt: null,
      ),
    ];
  }

  @override
  Future<Supplier?> findById(int id) => throw UnimplementedError();

  @override
  Future<int> create(SupplierInput input) => throw UnimplementedError();

  @override
  Future<void> update(int id, SupplierInput input) =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) => throw UnimplementedError();
}
