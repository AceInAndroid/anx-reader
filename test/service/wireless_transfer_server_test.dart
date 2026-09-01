import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/wireless_transfer_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'wirelessTransferAutoShutdown': 0,
    });
    await Prefs().initPrefs();
  });

  tearDown(() => WirelessTransferServer().stop());

  test('serves the batch upload client and exposes upload history', () async {
    final server = WirelessTransferServer();
    expect(await server.start(portOverride: 0), isTrue);

    final page = await _get('http://127.0.0.1:${server.port}/');
    expect(page.statusCode, HttpStatus.ok);
    final html = await utf8.decoder.bind(page).join();
    expect(html, contains('id="uploadHistory"'));
    expect(html, contains('multiple'));

    final request = await HttpClient().postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/upload-file'),
    );
    request.headers.contentType = ContentType.binary;
    request.headers.set('x-file-name', Uri.encodeComponent('notes.exe'));
    request.contentLength = 3;
    request.add(const [1, 2, 3]);
    final response = await request.close();
    expect(response.statusCode, HttpStatus.badRequest);
    await response.drain<void>();

    final statusResponse = await _get(
      'http://127.0.0.1:${server.port}/status',
    );
    final status = jsonDecode(await utf8.decoder.bind(statusResponse).join())
        as Map<String, dynamic>;
    final uploads = status['uploads'] as List<dynamic>;
    expect(uploads, isNotEmpty);
    expect(uploads.first, containsPair('filename', 'notes.exe'));
    expect(uploads.first, containsPair('success', false));
  });
}

Future<HttpClientResponse> _get(String url) async {
  return HttpClient().getUrl(Uri.parse(url)).then((request) => request.close());
}
