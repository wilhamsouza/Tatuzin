/// Only local destinations are accepted when returning from authentication.
/// Keep the original query string so search, filters and pagination survive.
String? ownerReturnLocation(String? target) {
  final parsed = target == null ? null : Uri.tryParse(target);
  if (target == null ||
      !target.startsWith('/') ||
      target.startsWith('//') ||
      target.contains('\\') ||
      parsed == null ||
      parsed.hasScheme ||
      parsed.hasAuthority ||
      parsed.path == '/login' ||
      parsed.path == '/') {
    return null;
  }
  return target;
}
