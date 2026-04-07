import 'dart:math';

abstract final class IdGenerator {
  static final Random _random = Random();

  static String next() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random
        .nextInt(0x7fffffff)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$timestamp-$suffix';
  }
}
