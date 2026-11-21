import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatuzin/app/core/session/app_session.dart';
import 'package:tatuzin/app/core/session/app_user.dart';
import 'package:tatuzin/app/core/session/cached_session_storage.dart';
import 'package:tatuzin/app/core/session/company_context.dart';
import 'package:tatuzin/modules/account/domain/company_receipt_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cache persists the profile and clears it when changing companies',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SharedPreferencesCachedSessionStorage();
      AppSession session(String id, CompanyExperienceProfile profile) =>
          AppSession(
            scope: SessionScope.authenticatedRemote,
            user: const AppUser(
              localId: null,
              remoteId: 'user',
              displayName: 'Dono',
              email: null,
              roleLabel: 'OWNER',
              kind: AppUserKind.remoteAuthenticated,
            ),
            company: CompanyContext(
              experienceRefreshEnabled: id == 'loja-a',
              onboardingEnabled: id == 'loja-a',
              localId: null,
              remoteId: id,
              displayName: id,
              legalName: id,
              documentNumber: null,
              experienceProfile: profile,
            ),
            startedAt: DateTime.now(),
            isOfflineFallback: false,
            clientInstanceId: 'device',
          );
      await storage.saveSession(
        session('loja-a', CompanyExperienceProfile.food),
      );
      expect(
        (await storage.readSession())!.company.experienceProfile,
        CompanyExperienceProfile.food,
      );
      expect(
        (await storage.readSession())!.company.experienceRefreshEnabled,
        true,
      );
      expect((await storage.readSession())!.company.onboardingEnabled, true);
      await storage.saveSession(
        session('loja-b', CompanyExperienceProfile.fashion),
      );
      expect((await storage.readSession())!.company.remoteId, 'loja-b');
      expect(
        (await storage.readSession())!.company.experienceRefreshEnabled,
        false,
      );
      expect((await storage.readSession())!.company.onboardingEnabled, false);
      expect(
        (await storage.readSession())!.company.experienceProfile,
        CompanyExperienceProfile.fashion,
      );
      await storage.clear();
      expect(await storage.readSession(), isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('session.cached.company_experience_profile'),
        isNull,
      );
    },
  );

  test('legacy and unknown profiles keep the mixed experience', () {
    expect(
      CompanyExperienceProfile.fromValue(null),
      CompanyExperienceProfile.mixed,
    );
    expect(
      CompanyExperienceProfile.fromValue('unknown'),
      CompanyExperienceProfile.mixed,
    );
    expect(
      CompanyExperienceProfile.fromValue('moda'),
      CompanyExperienceProfile.fashion,
    );
    expect(
      CompanyExperienceProfile.fromValue('alimentacao'),
      CompanyExperienceProfile.food,
    );
  });

  test('receipt patches do not silently overwrite the experience profile', () {
    final company = const CompanyContext.localDefault().copyWith(
      experienceProfile: CompanyExperienceProfile.food,
    );
    expect(
      CompanyReceiptSettingsDraft.fromCompany(
        company,
      ).toJson().containsKey('experienceProfile'),
      false,
    );
    expect(
      CompanyReceiptSettingsDraft.fromCompany(
        company,
        experienceProfile: CompanyExperienceProfile.fashion,
      ).toJson()['experienceProfile'],
      'moda',
    );
    final snapshot = CompanyReceiptSettingsSnapshot.fromJson({
      'company': {'name': 'Loja'},
    });
    expect(
      snapshot.mergeInto(company).experienceProfile,
      CompanyExperienceProfile.food,
    );
    expect(
      company.copyWith(displayName: 'Outra').experienceProfile,
      CompanyExperienceProfile.food,
    );
  });
}
