import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  tearDown(() => Server().stop());

  test('ensureStarted is idempotent for concurrent callers', () async {
    await Future.wait([
      Server().ensureStarted(),
      Server().ensureStarted(),
      Server().ensureStarted(),
    ]);

    final port = Server().port;
    expect(Server().isHealthy, isTrue);

    await Server().ensureStarted();
    expect(Server().port, port);
  });
}
