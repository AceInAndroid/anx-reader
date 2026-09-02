import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/models/reading_agent_sync.dart';
import 'package:anx_reader/service/sync/self_hosted_progress_sync_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProgressApiAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final headers = {
      Headers.contentTypeHeader: ['application/json']
    };
    if (options.path.endsWith('/v1/auth/login')) {
      return ResponseBody.fromString(
        '{"accessToken":"session-token",'
        '"expiresAt":"2026-10-02T12:00:00Z"}',
        200,
        headers: headers,
      );
    }
    if (options.path.contains('/v1/books/') &&
        options.path.endsWith('/progress') &&
        options.method == 'GET') {
      return ResponseBody.fromString(
        jsonEncode({
          'positions': [
            {
              'deviceId': 'remote-device',
              'locator': {'type': 'epub-cfi', 'value': 'remote-cfi'},
              'progress': .72,
              'chapterHref': 'chapter-7.xhtml',
              'chapterTitle': 'Chapter 7',
              'updatedAt': 200,
              'revision': 8,
            }
          ]
        }),
        200,
        headers: headers,
      );
    }
    if (options.path.contains('/v1/changes')) {
      return ResponseBody.fromString(
        jsonEncode({
          'nextCursor': '9',
          'changes': [
            {
              'bookKey': 'book-a',
              'deviceId': 'remote-device',
              'locator': {'type': 'epub-cfi', 'value': 'changed-cfi'},
              'progress': .8,
              'updatedAt': 300,
              'revision': 9,
            }
          ]
        }),
        200,
        headers: headers,
      );
    }
    return ResponseBody.fromString('{}', 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

class _ExpiredCursorAdapter implements HttpClientAdapter {
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final headers = {
      Headers.contentTypeHeader: ['application/json']
    };
    if (options.path.contains('?cursor=')) {
      return ResponseBody.fromString(
        '{"error":{"code":"cursor_expired"}}',
        409,
        headers: headers,
      );
    }
    return ResponseBody.fromString(
      '{"nextCursor":"12","changes":[]}',
      200,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('rejects endpoints that cannot protect account credentials', () {
    expect(
      () => SelfHostedProgressSyncTransport(
        endpoint: 'http://sync.example.test',
        accessToken: '',
        deviceId: 'local-device',
      ),
      throwsArgumentError,
    );
  });

  test('logs in, pings, and revokes the bearer session', () async {
    final adapter = _ProgressApiAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final unauthenticated = SelfHostedProgressSyncTransport(
      endpoint: 'https://sync.example.test/',
      accessToken: '',
      deviceId: 'local-device',
      dio: dio,
    );

    final session = await unauthenticated.login(
      username: ' reader ',
      password: 'password-123',
    );
    await unauthenticated.ping();
    final authenticated = SelfHostedProgressSyncTransport(
      endpoint: 'https://sync.example.test',
      accessToken: session.accessToken,
      deviceId: 'local-device',
      dio: dio,
    );
    await authenticated.logout();

    expect(session.accessToken, 'session-token');
    expect(session.expiresAt, DateTime.utc(2026, 10, 2, 12));
    expect(adapter.requests.first.data, {
      'username': 'reader',
      'password': 'password-123',
    });
    expect(adapter.requests[1].path, 'https://sync.example.test/health');
    expect(
        adapter.requests.last.headers['Authorization'], 'Bearer session-token');
  });

  test('uploads only the local device position table', () async {
    final adapter = _ProgressApiAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final transport = SelfHostedProgressSyncTransport(
      endpoint: 'https://sync.example.test',
      accessToken: 'session-token',
      deviceId: 'local-device',
      dio: dio,
    );

    await transport.uploadPackages([
      const ReadingAgentBookDelta(
        bookKey: 'md5:abc',
        deviceId: 'local-device',
        generatedAt: 200,
        rows: {
          'tb_book_device_positions': [
            {
              'device_id': 'local-device',
              'cfi': 'local-cfi',
              'progress': .42,
              'chapter_href': 'chapter-4.xhtml',
              'chapter_title': 'Chapter 4',
              'updated_at': 200,
            },
            {
              'device_id': 'remote-device',
              'cfi': 'remote-cfi',
              'progress': .72,
              'updated_at': 201,
            }
          ],
          'tb_reading_artifacts': [
            {'id': 'must-not-leave-device', 'payload_json': 'private'}
          ],
        },
      ),
    ]);

    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'PUT');
    expect(
      request.path,
      'https://sync.example.test/v1/books/md5%3Aabc/devices/'
      'local-device/progress',
    );
    expect(request.headers['Authorization'], 'Bearer session-token');
    expect(request.data, {
      'schemaVersion': 1,
      'bookKey': 'md5:abc',
      'deviceId': 'local-device',
      'locator': {'type': 'cfi', 'value': 'local-cfi'},
      'progress': .42,
      'chapterHref': 'chapter-4.xhtml',
      'chapterTitle': 'Chapter 4',
      'updatedAt': 200,
    });
    expect(jsonEncode(request.data), isNot(contains('payload_json')));
    expect(jsonEncode(request.data), isNot(contains('remote-cfi')));
  });

  test('maps book progress and cursor changes into position-only deltas',
      () async {
    final adapter = _ProgressApiAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final transport = SelfHostedProgressSyncTransport(
      endpoint: 'https://sync.example.test',
      accessToken: 'session-token',
      deviceId: 'local-device',
      dio: dio,
    );

    final downloaded = await transport.downloadPackages(['book-a']);
    final changes = await transport.downloadChanges(cursor: '8');

    expect(downloaded.single.bookKey, 'book-a');
    expect(downloaded.single.rows.keys, ['tb_book_device_positions']);
    expect(downloaded.single.rows['tb_book_device_positions']!.single, {
      'device_id': 'remote-device',
      'cfi': 'remote-cfi',
      'progress': .72,
      'chapter_href': 'chapter-7.xhtml',
      'chapter_title': 'Chapter 7',
      'updated_at': 200,
    });
    expect(changes.nextCursor, '9');
    expect(changes.packages.single.generatedAt, 300);
    expect(
      changes.packages.single.rows['tb_book_device_positions']!.single['cfi'],
      'changed-cfi',
    );
    expect(adapter.requests.last.path,
        'https://sync.example.test/v1/changes?cursor=8');
  });

  test('recovers an expired cursor with a full-state pull', () async {
    final adapter = _ExpiredCursorAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final transport = SelfHostedProgressSyncTransport(
      endpoint: 'https://sync.example.test',
      accessToken: 'session-token',
      deviceId: 'local-device',
      dio: dio,
    );

    final result = await transport.downloadChanges(cursor: '1');

    expect(result.nextCursor, '12');
    expect(adapter.paths, [
      'https://sync.example.test/v1/changes?cursor=1',
      'https://sync.example.test/v1/changes',
    ]);
  });
}
