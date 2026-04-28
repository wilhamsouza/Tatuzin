import 'package:erp_pdv_app/app/theme/app_theme.dart';
import 'package:erp_pdv_app/modules/produtos/domain/entities/product.dart';
import 'package:erp_pdv_app/modules/produtos/presentation/widgets/product_form/product_base_info_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('formulario de produto bloqueia campos obrigatorios invalidos', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final modelNameController = TextEditingController();
    final variantLabelController = TextEditingController();
    final descriptionController = TextEditingController();
    final barcodeController = TextEditingController();
    final costController = TextEditingController(text: '10');
    final priceController = TextEditingController(text: '0');
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
                categoryId: null,
                baseProductId: null,
                unitMeasure: 'un',
                isActive: true,
                categories: const [],
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

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text('Informe o nome do produto'), findsOneWidget);
    expect(find.text('Informe um preco de venda valido'), findsOneWidget);
  });
}
