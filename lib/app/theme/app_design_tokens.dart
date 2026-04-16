import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

@immutable
class AppTonePalette {
  const AppTonePalette({
    required this.base,
    required this.onBase,
    required this.surface,
    required this.onSurface,
    required this.border,
  });

  final Color base;
  final Color onBase;
  final Color surface;
  final Color onSurface;
  final Color border;

  AppTonePalette copyWith({
    Color? base,
    Color? onBase,
    Color? surface,
    Color? onSurface,
    Color? border,
  }) {
    return AppTonePalette(
      base: base ?? this.base,
      onBase: onBase ?? this.onBase,
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      border: border ?? this.border,
    );
  }

  static AppTonePalette lerp(AppTonePalette a, AppTonePalette b, double t) {
    return AppTonePalette(
      base: Color.lerp(a.base, b.base, t)!,
      onBase: Color.lerp(a.onBase, b.onBase, t)!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
      border: Color.lerp(a.border, b.border, t)!,
    );
  }
}

@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.pageBackground,
    required this.cardBackground,
    required this.sectionBackground,
    required this.raisedBackground,
    required this.sunkenBackground,
    required this.overlay,
    required this.outlineSoft,
    required this.outlineStrong,
    required this.shadowSoft,
    required this.brand,
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
    required this.sales,
    required this.cashflowPositive,
    required this.cashflowNegative,
    required this.stockLow,
    required this.interactive,
    required this.disabled,
    required this.selection,
  });

  final Color pageBackground;
  final Color cardBackground;
  final Color sectionBackground;
  final Color raisedBackground;
  final Color sunkenBackground;
  final Color overlay;
  final Color outlineSoft;
  final Color outlineStrong;
  final Color shadowSoft;
  final AppTonePalette brand;
  final AppTonePalette info;
  final AppTonePalette success;
  final AppTonePalette warning;
  final AppTonePalette danger;
  final AppTonePalette sales;
  final AppTonePalette cashflowPositive;
  final AppTonePalette cashflowNegative;
  final AppTonePalette stockLow;
  final AppTonePalette interactive;
  final AppTonePalette disabled;
  final AppTonePalette selection;

  @override
  AppColorTokens copyWith({
    Color? pageBackground,
    Color? cardBackground,
    Color? sectionBackground,
    Color? raisedBackground,
    Color? sunkenBackground,
    Color? overlay,
    Color? outlineSoft,
    Color? outlineStrong,
    Color? shadowSoft,
    AppTonePalette? brand,
    AppTonePalette? info,
    AppTonePalette? success,
    AppTonePalette? warning,
    AppTonePalette? danger,
    AppTonePalette? sales,
    AppTonePalette? cashflowPositive,
    AppTonePalette? cashflowNegative,
    AppTonePalette? stockLow,
    AppTonePalette? interactive,
    AppTonePalette? disabled,
    AppTonePalette? selection,
  }) {
    return AppColorTokens(
      pageBackground: pageBackground ?? this.pageBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      sectionBackground: sectionBackground ?? this.sectionBackground,
      raisedBackground: raisedBackground ?? this.raisedBackground,
      sunkenBackground: sunkenBackground ?? this.sunkenBackground,
      overlay: overlay ?? this.overlay,
      outlineSoft: outlineSoft ?? this.outlineSoft,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      shadowSoft: shadowSoft ?? this.shadowSoft,
      brand: brand ?? this.brand,
      info: info ?? this.info,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      sales: sales ?? this.sales,
      cashflowPositive: cashflowPositive ?? this.cashflowPositive,
      cashflowNegative: cashflowNegative ?? this.cashflowNegative,
      stockLow: stockLow ?? this.stockLow,
      interactive: interactive ?? this.interactive,
      disabled: disabled ?? this.disabled,
      selection: selection ?? this.selection,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) {
      return this;
    }

    return AppColorTokens(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      sectionBackground: Color.lerp(
        sectionBackground,
        other.sectionBackground,
        t,
      )!,
      raisedBackground: Color.lerp(
        raisedBackground,
        other.raisedBackground,
        t,
      )!,
      sunkenBackground: Color.lerp(
        sunkenBackground,
        other.sunkenBackground,
        t,
      )!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      outlineSoft: Color.lerp(outlineSoft, other.outlineSoft, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      shadowSoft: Color.lerp(shadowSoft, other.shadowSoft, t)!,
      brand: AppTonePalette.lerp(brand, other.brand, t),
      info: AppTonePalette.lerp(info, other.info, t),
      success: AppTonePalette.lerp(success, other.success, t),
      warning: AppTonePalette.lerp(warning, other.warning, t),
      danger: AppTonePalette.lerp(danger, other.danger, t),
      sales: AppTonePalette.lerp(sales, other.sales, t),
      cashflowPositive: AppTonePalette.lerp(
        cashflowPositive,
        other.cashflowPositive,
        t,
      ),
      cashflowNegative: AppTonePalette.lerp(
        cashflowNegative,
        other.cashflowNegative,
        t,
      ),
      stockLow: AppTonePalette.lerp(stockLow, other.stockLow, t),
      interactive: AppTonePalette.lerp(interactive, other.interactive, t),
      disabled: AppTonePalette.lerp(disabled, other.disabled, t),
      selection: AppTonePalette.lerp(selection, other.selection, t),
    );
  }
}

@immutable
class AppLayoutTokens extends ThemeExtension<AppLayoutTokens> {
  const AppLayoutTokens({
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXl,
    required this.radiusSheet,
    required this.radiusPill,
    required this.space2,
    required this.space3,
    required this.space4,
    required this.space5,
    required this.space6,
    required this.space7,
    required this.space8,
    required this.space9,
    required this.space10,
    required this.space11,
    required this.pagePadding,
    required this.pagePaddingCompact,
    required this.sectionGap,
    required this.blockGap,
    required this.gridGap,
    required this.iconSm,
    required this.iconMd,
    required this.iconLg,
    required this.inputHeight,
    required this.actionHeight,
    required this.compactActionHeight,
    required this.quickActionHeight,
    required this.cardPadding,
    required this.compactCardPadding,
    required this.headerPadding,
    required this.bottomBarPadding,
    required this.sheetPadding,
    required this.shadowBlur,
    required this.shadowOffsetY,
  });

  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusXl;
  final double radiusSheet;
  final double radiusPill;
  final double space2;
  final double space3;
  final double space4;
  final double space5;
  final double space6;
  final double space7;
  final double space8;
  final double space9;
  final double space10;
  final double space11;
  final double pagePadding;
  final double pagePaddingCompact;
  final double sectionGap;
  final double blockGap;
  final double gridGap;
  final double iconSm;
  final double iconMd;
  final double iconLg;
  final double inputHeight;
  final double actionHeight;
  final double compactActionHeight;
  final double quickActionHeight;
  final double cardPadding;
  final double compactCardPadding;
  final double headerPadding;
  final double bottomBarPadding;
  final double sheetPadding;
  final double shadowBlur;
  final double shadowOffsetY;

  @override
  AppLayoutTokens copyWith({
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXl,
    double? radiusSheet,
    double? radiusPill,
    double? space2,
    double? space3,
    double? space4,
    double? space5,
    double? space6,
    double? space7,
    double? space8,
    double? space9,
    double? space10,
    double? space11,
    double? pagePadding,
    double? pagePaddingCompact,
    double? sectionGap,
    double? blockGap,
    double? gridGap,
    double? iconSm,
    double? iconMd,
    double? iconLg,
    double? inputHeight,
    double? actionHeight,
    double? compactActionHeight,
    double? quickActionHeight,
    double? cardPadding,
    double? compactCardPadding,
    double? headerPadding,
    double? bottomBarPadding,
    double? sheetPadding,
    double? shadowBlur,
    double? shadowOffsetY,
  }) {
    return AppLayoutTokens(
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
      radiusSheet: radiusSheet ?? this.radiusSheet,
      radiusPill: radiusPill ?? this.radiusPill,
      space2: space2 ?? this.space2,
      space3: space3 ?? this.space3,
      space4: space4 ?? this.space4,
      space5: space5 ?? this.space5,
      space6: space6 ?? this.space6,
      space7: space7 ?? this.space7,
      space8: space8 ?? this.space8,
      space9: space9 ?? this.space9,
      space10: space10 ?? this.space10,
      space11: space11 ?? this.space11,
      pagePadding: pagePadding ?? this.pagePadding,
      pagePaddingCompact: pagePaddingCompact ?? this.pagePaddingCompact,
      sectionGap: sectionGap ?? this.sectionGap,
      blockGap: blockGap ?? this.blockGap,
      gridGap: gridGap ?? this.gridGap,
      iconSm: iconSm ?? this.iconSm,
      iconMd: iconMd ?? this.iconMd,
      iconLg: iconLg ?? this.iconLg,
      inputHeight: inputHeight ?? this.inputHeight,
      actionHeight: actionHeight ?? this.actionHeight,
      compactActionHeight: compactActionHeight ?? this.compactActionHeight,
      quickActionHeight: quickActionHeight ?? this.quickActionHeight,
      cardPadding: cardPadding ?? this.cardPadding,
      compactCardPadding: compactCardPadding ?? this.compactCardPadding,
      headerPadding: headerPadding ?? this.headerPadding,
      bottomBarPadding: bottomBarPadding ?? this.bottomBarPadding,
      sheetPadding: sheetPadding ?? this.sheetPadding,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
    );
  }

  @override
  AppLayoutTokens lerp(ThemeExtension<AppLayoutTokens>? other, double t) {
    if (other is! AppLayoutTokens) {
      return this;
    }

    return AppLayoutTokens(
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t)!,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t)!,
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t)!,
      radiusXl: lerpDouble(radiusXl, other.radiusXl, t)!,
      radiusSheet: lerpDouble(radiusSheet, other.radiusSheet, t)!,
      radiusPill: lerpDouble(radiusPill, other.radiusPill, t)!,
      space2: lerpDouble(space2, other.space2, t)!,
      space3: lerpDouble(space3, other.space3, t)!,
      space4: lerpDouble(space4, other.space4, t)!,
      space5: lerpDouble(space5, other.space5, t)!,
      space6: lerpDouble(space6, other.space6, t)!,
      space7: lerpDouble(space7, other.space7, t)!,
      space8: lerpDouble(space8, other.space8, t)!,
      space9: lerpDouble(space9, other.space9, t)!,
      space10: lerpDouble(space10, other.space10, t)!,
      space11: lerpDouble(space11, other.space11, t)!,
      pagePadding: lerpDouble(pagePadding, other.pagePadding, t)!,
      pagePaddingCompact: lerpDouble(
        pagePaddingCompact,
        other.pagePaddingCompact,
        t,
      )!,
      sectionGap: lerpDouble(sectionGap, other.sectionGap, t)!,
      blockGap: lerpDouble(blockGap, other.blockGap, t)!,
      gridGap: lerpDouble(gridGap, other.gridGap, t)!,
      iconSm: lerpDouble(iconSm, other.iconSm, t)!,
      iconMd: lerpDouble(iconMd, other.iconMd, t)!,
      iconLg: lerpDouble(iconLg, other.iconLg, t)!,
      inputHeight: lerpDouble(inputHeight, other.inputHeight, t)!,
      actionHeight: lerpDouble(actionHeight, other.actionHeight, t)!,
      compactActionHeight: lerpDouble(
        compactActionHeight,
        other.compactActionHeight,
        t,
      )!,
      quickActionHeight: lerpDouble(
        quickActionHeight,
        other.quickActionHeight,
        t,
      )!,
      cardPadding: lerpDouble(cardPadding, other.cardPadding, t)!,
      compactCardPadding: lerpDouble(
        compactCardPadding,
        other.compactCardPadding,
        t,
      )!,
      headerPadding: lerpDouble(headerPadding, other.headerPadding, t)!,
      bottomBarPadding: lerpDouble(
        bottomBarPadding,
        other.bottomBarPadding,
        t,
      )!,
      sheetPadding: lerpDouble(sheetPadding, other.sheetPadding, t)!,
      shadowBlur: lerpDouble(shadowBlur, other.shadowBlur, t)!,
      shadowOffsetY: lerpDouble(shadowOffsetY, other.shadowOffsetY, t)!,
    );
  }
}

extension AppThemeTokensX on BuildContext {
  AppColorTokens get appColors => Theme.of(this).extension<AppColorTokens>()!;

  AppLayoutTokens get appLayout => Theme.of(this).extension<AppLayoutTokens>()!;
}
