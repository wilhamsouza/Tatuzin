import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/onboarding_progress.dart';

class OnboardingStorage {
  String _key(String companyId) =>
      'company.onboarding.v1.${Uri.encodeComponent(companyId)}';

  Future<OnboardingProgress> read(String companyId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key(companyId));
      if (raw == null) return const OnboardingProgress();
      return OnboardingProgress.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const OnboardingProgress();
    }
  }

  Future<void> save(String companyId, OnboardingProgress progress) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(companyId), jsonEncode(progress.toJson()));
  }
}
