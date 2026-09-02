import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/ai/reading_device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates one stable installation id', () async {
    SharedPreferences.setMockInitialValues({});
    Prefs().prefs = await SharedPreferences.getInstance();
    final identity = ReadingDeviceIdentity();

    final first = await identity.getOrCreate();
    final second = await identity.getOrCreate();

    expect(first, isNotEmpty);
    expect(second, first);
    expect(Prefs().prefs.getString(ReadingDeviceIdentity.preferenceKey), first);
  });

  test('installation id is neither exported nor overwritten by backup',
      () async {
    SharedPreferences.setMockInitialValues({
      ReadingDeviceIdentity.preferenceKey: 'this-device',
    });
    Prefs().prefs = await SharedPreferences.getInstance();

    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup, isNot(contains(ReadingDeviceIdentity.preferenceKey)));

    await Prefs().applyPrefsBackupMap({
      ReadingDeviceIdentity.preferenceKey: {
        'type': 'string',
        'value': 'other-device',
      },
    });
    expect(
      Prefs().prefs.getString(ReadingDeviceIdentity.preferenceKey),
      'this-device',
    );
  });

  test('CloudBase account token is excluded from normal backup', () async {
    SharedPreferences.setMockInitialValues({
      'cloudBaseSyncEndpoint': 'https://sync.example.test',
      'cloudBaseSyncAccountToken': 'account-secret-token',
    });
    Prefs().prefs = await SharedPreferences.getInstance();

    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup, contains('cloudBaseSyncEndpoint'));
    expect(backup, isNot(contains('cloudBaseSyncAccountToken')));

    await Prefs().applyPrefsBackupMap({
      'cloudBaseSyncAccountToken': {
        'type': 'string',
        'value': 'overwritten-account-token',
      },
    });
    expect(Prefs().cloudBaseSyncAccountToken, 'account-secret-token');
  });

  test('CloudBase sync uses the deployed endpoint by default', () async {
    SharedPreferences.setMockInitialValues({});
    Prefs().prefs = await SharedPreferences.getInstance();

    expect(Prefs().cloudBaseSyncEndpoint, defaultCloudBaseSyncEndpoint);
    expect(Prefs().cloudBaseSyncEnabled, isFalse);
  });

  test('self-hosted progress endpoint and session stay device-local', () async {
    SharedPreferences.setMockInitialValues({
      'selfHostedProgressSyncEndpoint': 'https://progress.example.test',
      'selfHostedProgressSyncEnabled': true,
      'selfHostedProgressSyncToken': 'private-session',
      'selfHostedProgressSyncTokenExpiresAt': 123,
      'selfHostedProgressSyncCursor': '42',
    });
    Prefs().prefs = await SharedPreferences.getInstance();

    final backup = await Prefs().buildPrefsBackupMap();

    expect(backup, isNot(contains('selfHostedProgressSyncEndpoint')));
    expect(backup, isNot(contains('selfHostedProgressSyncEnabled')));
    expect(backup, isNot(contains('selfHostedProgressSyncToken')));
    expect(backup, isNot(contains('selfHostedProgressSyncTokenExpiresAt')));
    expect(backup, isNot(contains('selfHostedProgressSyncCursor')));
    await Prefs().applyPrefsBackupMap({
      'selfHostedProgressSyncEndpoint': {
        'type': 'string',
        'value': 'https://attacker.example.test',
      },
      'selfHostedProgressSyncToken': {
        'type': 'string',
        'value': 'replacement-token',
      },
    });
    expect(Prefs().selfHostedProgressSyncEndpoint,
        'https://progress.example.test');
    expect(Prefs().selfHostedProgressSyncToken, 'private-session');
  });
}
