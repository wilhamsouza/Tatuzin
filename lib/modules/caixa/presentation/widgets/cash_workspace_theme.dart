import 'package:flutter/material.dart';
import '../../../../app/core/widgets/product_stock_surface.dart';

/// Reuses Tatuzin's purple surfaces within the cash workspace only.
class CashWorkspaceTheme extends StatelessWidget {
  const CashWorkspaceTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ProductStockSurface(child: child);
}
