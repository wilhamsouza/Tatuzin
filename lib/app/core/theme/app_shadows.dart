import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const sm = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static const md = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const lg = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 32, offset: Offset(0, 8)),
  ];
}
