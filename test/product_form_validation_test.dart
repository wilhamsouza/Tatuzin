import 'package:tatuzin/app/theme/app_theme.dart';
import 'package:tatuzin/modules/categorias/domain/entities/category.dart';
import 'package:tatuzin/modules/produtos/domain/entities/product.dart';
import 'package:tatuzin/modules/produtos/presentation/widgets/product_form/product_base_info_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('formulario de produto bloqueia campos obrigatorios invalidos', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await _pumpBaseInfoSection(
      tester,
      formKey: formKey,
      name: '',
      categoryId: null,
      price: '0',
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text('Informe o nome do produto'), findsOneWidget);
    expect(find.text('Informe a categoria do produto'), findsOneWidget);
    expect(find.text('Informe um preco de venda valido'), findsOneWidget);
  });

  testWidgets('formulario de produto informa categoria obrigatoria', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await _pumpBaseInfoSection(
      tester,
      formKey: formKey,
      name: 'Camiseta Basic',
      categoryId: null,
      price: '59,90',
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text('Informe o nome do produto'), findsNothing);
    expect(find.text('Informe a categoria do produto'), findsOneWidget);
  });

  testWidgets('formulario de produto valido passa sem erro de nome/categoria', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await _pumpBaseInfoSection(
      tester,
      formKey: formKey,
      name: 'Camiseta Basic',
      categoryId: 1,
      price: '59,90',
    );

    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();

    expect(find.text('Informe o nome do produto'), findsNothing);
    expect(find.text('Informe a categoria do produto'), findsNothing);
  });
}

Future<void> _pumpBaseInfoSection(
  WidgetTester tester, {
  required GlobalKey<FormState> formKey,
  required String name,
  required int? categoryId,
  required String price,
}) async {
  final nameController = TextEditingController(text: name);
  final modelNameController = TextEditingController();
  final variantLabelController = TextEditingController();
  final descriptionController = TextEditingController();
  final barcodeController = TextEditingController();
  final costController = TextEditingController(text: '10');
  final priceController = TextEditingController(text: price);
  final stockController = TextEditingController(text: '6');
  addTearDown(() {
    nameController.dispose();
    modelNameController.dispose();
    variantLabelController.dispose();
    descriptionController.dispose();
    barcodeController.dispose();
    costController.dispose();
    priceController.dispose();
    stockController.dispose();
  });

  final now = DateTime(2026);
  final categories = [
    Category(
      id: 1,
      uuid: 'category-1',
      name: 'Roupas',
      description: null,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    ),
  ];

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: ProductBaseInfoSection(
              isEditing: false,
              selectedNiche: ProductNiches.food,
              selectedCatalogType: ProductCatalogTypes.simple,
              usesVariantStock: false,
              activeVariantCount: 0,
              nameController: nameController,
              modelNameController: modelNameController,
              variantLabelController: variantLabelController,
              descriptionController: descriptionController,
              barcodeController: barcodeController,
              costController: costController,
              priceController: priceController,
              stockController: stockController,
              categoryId: categoryId,
              baseProductId: null,
              unitMeasure: 'un',
              isActive: true,
              categories: categories,
              baseProducts: const [],
              isCategoryLoading: false,
              isBaseProductLoading: false,
              onCategoryChanged: (_) {},
              onBaseProductChanged: (_) {},
              onUnitMeasureChanged: (_) {},
              onActiveChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}
