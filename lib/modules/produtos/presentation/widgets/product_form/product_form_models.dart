import '../../../../../app/core/formatters/app_formatters.dart';
import '../../../../../app/core/utils/money_parser.dart';
import '../../../../../app/core/utils/quantity_parser.dart';
import '../../../domain/entities/product.dart';

class EditableProductPhoto {
  const EditableProductPhoto({
    required this.localPath,
    required this.isPrimary,
  });

  final String localPath;
  final bool isPrimary;

  EditableProductPhoto copyWith({String? localPath, bool? isPrimary}) {
    return EditableProductPhoto(
      localPath: localPath ?? this.localPath,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
}

class EditableModifierGroup {
  const EditableModifierGroup({
    required this.name,
    required this.isRequired,
    required this.minSelections,
    required this.maxSelections,
    required this.options,
  });

  final String name;
  final bool isRequired;
  final int minSelections;
  final int? maxSelections;
  final List<EditableModifierOption> options;

  EditableModifierGroup copyWith({
    String? name,
    bool? isRequired,
    int? minSelections,
    int? maxSelections,
    List<EditableModifierOption>? options,
  }) {
    return EditableModifierGroup(
      name: name ?? this.name,
      isRequired: isRequired ?? this.isRequired,
      minSelections: minSelections ?? this.minSelections,
      maxSelections: maxSelections ?? this.maxSelections,
      options: options ?? this.options,
    );
  }

  factory EditableModifierGroup.fromProduct(ProductModifierGroup group) {
    return EditableModifierGroup(
      name: group.name,
      isRequired: group.isRequired,
      minSelections: group.minSelections,
      maxSelections: group.maxSelections,
      options: group.options
          .map(EditableModifierOption.fromProduct)
          .toList(growable: false),
    );
  }
}

class EditableModifierOption {
  const EditableModifierOption({
    required this.name,
    required this.adjustmentType,
    required this.priceDeltaCents,
  });

  final String name;
  final String adjustmentType;
  final int priceDeltaCents;

  factory EditableModifierOption.fromProduct(ProductModifierOption option) {
    return EditableModifierOption(
      name: option.name,
      adjustmentType: option.adjustmentType,
      priceDeltaCents: option.priceDeltaCents,
    );
  }
}

class FashionGridVariantDraft {
  const FashionGridVariantDraft({
    required this.sizeLabel,
    required this.colorLabel,
    required this.stockMil,
    required this.sku,
    this.priceAdditionalCents = 0,
    this.isActive = true,
  });

  final String sizeLabel;
  final String colorLabel;
  final int stockMil;
  final String sku;
  final int priceAdditionalCents;
  final bool isActive;

  String get stockLabel => AppFormatters.quantityFromMil(stockMil);

  String get priceAdditionalLabel =>
      AppFormatters.currencyInputFromCents(priceAdditionalCents);

  FashionGridVariantDraft copyWith({
    String? sizeLabel,
    String? colorLabel,
    int? stockMil,
    String? sku,
    int? priceAdditionalCents,
    bool? isActive,
  }) {
    return FashionGridVariantDraft(
      sizeLabel: sizeLabel ?? this.sizeLabel,
      colorLabel: colorLabel ?? this.colorLabel,
      stockMil: stockMil ?? this.stockMil,
      sku: sku ?? this.sku,
      priceAdditionalCents: priceAdditionalCents ?? this.priceAdditionalCents,
      isActive: isActive ?? this.isActive,
    );
  }

  factory FashionGridVariantDraft.fromProduct(ProductVariant variant) {
    return FashionGridVariantDraft(
      sizeLabel: variant.sizeLabel,
      colorLabel: variant.colorLabel,
      stockMil: variant.stockMil,
      sku: variant.sku,
      priceAdditionalCents: variant.priceAdditionalCents,
      isActive: variant.isActive,
    );
  }
}

class FashionGridDraft {
  const FashionGridDraft({
    this.sizes = const <String>[],
    this.colors = const <String>[],
    this.variants = const <FashionGridVariantDraft>[],
  });

  final List<String> sizes;
  final List<String> colors;
  final List<FashionGridVariantDraft> variants;

  bool get hasDimensions => sizes.isNotEmpty && colors.isNotEmpty;

  int get combinationCount => sizes.length * colors.length;

  int get activeVariantCount {
    if (!hasDimensions) {
      return 0;
    }

    var total = 0;
    for (final size in sizes) {
      for (final color in colors) {
        if (resolveCell(size, color, skuSeed: 'PRODUTO').isActive) {
          total++;
        }
      }
    }
    return total;
  }

  int get totalStockMil {
    if (!hasDimensions) {
      return 0;
    }

    var total = 0;
    for (final size in sizes) {
      for (final color in colors) {
        total += resolveCell(size, color, skuSeed: 'PRODUTO').stockMil;
      }
    }
    return total;
  }

  FashionGridDraft copyWith({
    List<String>? sizes,
    List<String>? colors,
    List<FashionGridVariantDraft>? variants,
  }) {
    return FashionGridDraft(
      sizes: sizes ?? this.sizes,
      colors: colors ?? this.colors,
      variants: variants ?? this.variants,
    );
  }

  FashionGridDraft addSize(String size) {
    final trimmed = size.trim();
    if (trimmed.isEmpty || sizes.contains(trimmed)) {
      return this;
    }
    return copyWith(sizes: <String>[...sizes, trimmed]);
  }

  FashionGridDraft addColor(String color) {
    final trimmed = color.trim();
    if (trimmed.isEmpty || colors.contains(trimmed)) {
      return this;
    }
    return copyWith(colors: <String>[...colors, trimmed]);
  }

  FashionGridDraft removeSize(String size) {
    return copyWith(
      sizes: sizes.where((current) => current != size).toList(growable: false),
      variants: variants
          .where((variant) => variant.sizeLabel.trim() != size.trim())
          .toList(growable: false),
    );
  }

  FashionGridDraft removeColor(String color) {
    return copyWith(
      colors: colors
          .where((current) => current != color)
          .toList(growable: false),
      variants: variants
          .where((variant) => variant.colorLabel.trim() != color.trim())
          .toList(growable: false),
    );
  }

  FashionGridDraft upsertVariant(FashionGridVariantDraft variant) {
    final updated = <FashionGridVariantDraft>[];
    var replaced = false;
    for (final current in variants) {
      final sameCell =
          current.sizeLabel.trim() == variant.sizeLabel.trim() &&
          current.colorLabel.trim() == variant.colorLabel.trim();
      if (sameCell) {
        updated.add(variant);
        replaced = true;
      } else {
        updated.add(current);
      }
    }
    if (!replaced) {
      updated.add(variant);
    }
    return copyWith(variants: updated);
  }

  FashionGridVariantDraft resolveCell(
    String size,
    String color, {
    required String skuSeed,
  }) {
    for (final variant in variants) {
      final sameCell =
          variant.sizeLabel.trim() == size.trim() &&
          variant.colorLabel.trim() == color.trim();
      if (sameCell) {
        return variant;
      }
    }

    return FashionGridVariantDraft(
      sizeLabel: size,
      colorLabel: color,
      stockMil: 0,
      sku: buildDefaultSku(skuSeed, size, color),
    );
  }

  List<ProductVariantInput> toVariantInputs({required String skuSeed}) {
    if (!hasDimensions) {
      return const <ProductVariantInput>[];
    }

    final inputs = <ProductVariantInput>[];
    var sortOrder = 0;
    for (final size in sizes) {
      for (final color in colors) {
        final cell = resolveCell(size, color, skuSeed: skuSeed);
        inputs.add(
          ProductVariantInput(
            sku:
                _cleanNullable(cell.sku) ??
                buildDefaultSku(skuSeed, size, color),
            colorLabel: color.trim(),
            sizeLabel: size.trim(),
            priceAdditionalCents: cell.priceAdditionalCents,
            stockMil: cell.stockMil,
            sortOrder: sortOrder++,
            isActive: cell.isActive,
          ),
        );
      }
    }
    return inputs;
  }

  String? buildHintValue() {
    if (sizes.isEmpty && colors.isEmpty) {
      return null;
    }

    final parts = <String>[];
    if (sizes.isNotEmpty) {
      parts.add('sizes=${sizes.join('|')}');
    }
    if (colors.isNotEmpty) {
      parts.add('colors=${colors.join('|')}');
    }
    return parts.join(';');
  }

  factory FashionGridDraft.fromExisting({
    String? gridHint,
    Iterable<ProductVariant> variants = const <ProductVariant>[],
  }) {
    final parsed = _parseGridHint(gridHint);
    final sizes = <String>[...parsed.sizes];
    final colors = <String>[...parsed.colors];
    final drafts = <FashionGridVariantDraft>[];

    for (final variant in variants) {
      final size = variant.sizeLabel.trim();
      final color = variant.colorLabel.trim();
      if (size.isNotEmpty && !sizes.contains(size)) {
        sizes.add(size);
      }
      if (color.isNotEmpty && !colors.contains(color)) {
        colors.add(color);
      }
      drafts.add(FashionGridVariantDraft.fromProduct(variant));
    }

    return FashionGridDraft(sizes: sizes, colors: colors, variants: drafts);
  }

  static String buildDefaultSku(String skuSeed, String size, String color) {
    final fallbackBase = _normalizeSkuToken(skuSeed).isEmpty
        ? 'PRODUTO'
        : _normalizeSkuToken(skuSeed);
    final normalizedSize = _normalizeSkuToken(size);
    final normalizedColor = _normalizeSkuToken(color);
    return '$fallbackBase-$normalizedSize-$normalizedColor';
  }

  static _ParsedFashionGridHint _parseGridHint(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      return const _ParsedFashionGridHint();
    }

    final sizes = <String>[];
    final colors = <String>[];
    for (final section in text.split(';')) {
      final separator = section.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = section.substring(0, separator).trim().toLowerCase();
      final values = section
          .substring(separator + 1)
          .split('|')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (key == 'sizes') {
        for (final value in values) {
          if (!sizes.contains(value)) {
            sizes.add(value);
          }
        }
      } else if (key == 'colors') {
        for (final value in values) {
          if (!colors.contains(value)) {
            colors.add(value);
          }
        }
      }
    }
    return _ParsedFashionGridHint(sizes: sizes, colors: colors);
  }

  static String _normalizeSkuToken(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  static String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _ParsedFashionGridHint {
  const _ParsedFashionGridHint({
    this.sizes = const <String>[],
    this.colors = const <String>[],
  });

  final List<String> sizes;
  final List<String> colors;
}

int parseStockMilLabel(String value) => QuantityParser.parseToMil(value);

int parsePriceAdditionalCents(String value) => MoneyParser.parseToCents(value);
