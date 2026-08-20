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
}
