import 'package:anx_reader/models/reading_agent_sync.dart';
import 'package:anx_reader/service/sync/reading_agent_sync_transport.dart';
import 'package:dio/dio.dart';

/// Session returned by the self-hosted progress API.
class SelfHostedProgressSyncSession {
  const SelfHostedProgressSyncSession({
    required this.accessToken,
    required this.expiresAt,
  });

  final String accessToken;
  final DateTime expiresAt;
}

class SelfHostedProgressSyncChanges {
  const SelfHostedProgressSyncChanges({
    required this.packages,
    required this.nextCursor,
  });

  final List<ReadingAgentBookDelta> packages;
  final String nextCursor;
}

/// Transport for the small, progress-only API. It deliberately strips every
/// table except [tb_book_device_positions] before making a request.
class SelfHostedProgressSyncTransport implements ReadingAgentSyncTransport {
  SelfHostedProgressSyncTransport({
    required String endpoint,
    required this.accessToken,
    required this.deviceId,
    Dio? dio,
  })  : endpoint = _normalizeEndpoint(endpoint),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
            ));

  final String endpoint;
  final String accessToken;
  final String deviceId;
  final Dio _dio;

  Options get _options => Options(headers: {
        if (accessToken.trim().isNotEmpty)
          'Authorization': 'Bearer ${accessToken.trim()}',
        'Content-Type': 'application/json',
      });

  Future<SelfHostedProgressSyncSession> login({
    required String username,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$endpoint/v1/auth/login',
      data: {'username': username.trim(), 'password': password},
    );
    final data = response.data ?? const <String, dynamic>{};
    final token = data['accessToken']?.toString() ?? '';
    if (token.isEmpty) {
      throw const FormatException(
          'Self-hosted progress login response is invalid');
    }
    final expiresAt = _parseDate(data['expiresAt']);
    if (expiresAt == null) {
      throw const FormatException(
          'Self-hosted progress session expiry is invalid');
    }
    return SelfHostedProgressSyncSession(
      accessToken: token,
      expiresAt: expiresAt,
    );
  }

  Future<void> logout() async {
    if (accessToken.trim().isEmpty) return;
    await _dio.post<void>('$endpoint/v1/auth/logout', options: _options);
  }

  @override
  Future<void> ping() async {
    await _dio.get<void>('$endpoint/health');
  }

  @override
  Future<List<ReadingAgentBookDelta>> downloadPackages(
    Iterable<String> bookKeys,
  ) async {
    final packages = <ReadingAgentBookDelta>[];
    for (final bookKey in bookKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()) {
      final response = await _dio.get<Map<String, dynamic>>(
        '$endpoint/v1/books/${Uri.encodeComponent(bookKey)}/progress',
        options: _options,
      );
      final positions = response.data?['positions'];
      if (positions is! List) continue;
      for (final raw in positions.whereType<Map>()) {
        final row = _positionRow(Map<String, dynamic>.from(raw));
        if (row == null) continue;
        final remoteDevice = row['device_id']?.toString() ?? '';
        if (remoteDevice.isEmpty) continue;
        packages.add(ReadingAgentBookDelta(
          bookKey: bookKey,
          deviceId: remoteDevice,
          generatedAt: _asInt(row['updated_at']),
          rows: {
            'tb_book_device_positions': [row]
          },
        ));
      }
    }
    return packages;
  }

  /// Pulls the server's append-only change feed. This is available to a
  /// coordinator that persists a cursor; the legacy transport interface keeps
  /// per-book downloads for compatibility with [ReadingAgentSyncService].
  Future<SelfHostedProgressSyncChanges> downloadChanges(
      {String? cursor}) async {
    try {
      return await _downloadChanges(cursor);
    } on DioException catch (error) {
      final body = error.response?.data;
      final details = body is Map ? body['error'] : null;
      final code = details is Map ? details['code']?.toString() : null;
      if ((cursor?.isNotEmpty ?? false) &&
          error.response?.statusCode == 409 &&
          code == 'cursor_expired') {
        return _downloadChanges(null);
      }
      rethrow;
    }
  }

  Future<SelfHostedProgressSyncChanges> _downloadChanges(String? cursor) async {
    final query = (cursor == null || cursor.isEmpty)
        ? ''
        : '?cursor=${Uri.encodeQueryComponent(cursor)}';
    final response = await _dio.get<Map<String, dynamic>>(
      '$endpoint/v1/changes$query',
      options: _options,
    );
    final rawChanges = response.data?['changes'];
    final packages = <ReadingAgentBookDelta>[];
    if (rawChanges is List) {
      for (final raw in rawChanges.whereType<Map>()) {
        final value = Map<String, dynamic>.from(raw);
        final row = _positionRow(value);
        final bookKey = value['bookKey']?.toString() ?? '';
        final remoteDevice = value['deviceId']?.toString() ?? '';
        if (row == null || bookKey.isEmpty || remoteDevice.isEmpty) continue;
        packages.add(ReadingAgentBookDelta(
          bookKey: bookKey,
          deviceId: remoteDevice,
          generatedAt: _asInt(value['updatedAt'] ?? row['updated_at']),
          rows: {
            'tb_book_device_positions': [row]
          },
        ));
      }
    }
    return SelfHostedProgressSyncChanges(
      packages: packages,
      nextCursor: response.data?['nextCursor']?.toString() ?? cursor ?? '',
    );
  }

  @override
  Future<void> uploadPackages(
    Iterable<ReadingAgentBookDelta> packages,
  ) async {
    for (final package in packages) {
      for (final raw in package.rows['tb_book_device_positions'] ?? const []) {
        final rowDevice = raw['device_id']?.toString() ?? package.deviceId;
        if (rowDevice != package.deviceId || package.deviceId != deviceId) {
          continue;
        }
        final row = _positionRow(raw);
        if (row == null) continue;
        await _dio.put<void>(
          '$endpoint/v1/books/${Uri.encodeComponent(package.bookKey)}'
          '/devices/${Uri.encodeComponent(deviceId)}/progress',
          data: {
            'schemaVersion': 1,
            'bookKey': package.bookKey,
            'deviceId': deviceId,
            'locator': {
              'type': 'cfi',
              'value': row['cfi'],
            },
            'progress': row['progress'],
            if (row['chapter_href'] != null) 'chapterHref': row['chapter_href'],
            if (row['chapter_title'] != null)
              'chapterTitle': row['chapter_title'],
            'updatedAt': row['updated_at'],
          },
          options: _options,
        );
      }
    }
  }

  static Map<String, dynamic>? _positionRow(Map<String, dynamic> value) {
    final locator = value['locator'];
    final locatorMap = locator is Map
        ? Map<String, dynamic>.from(locator)
        : const <String, dynamic>{};
    final cfi =
        value['cfi']?.toString() ?? locatorMap['value']?.toString() ?? '';
    final deviceId =
        value['device_id']?.toString() ?? value['deviceId']?.toString() ?? '';
    final progress = value['progress'];
    final updatedAt = value['updated_at'] ?? value['updatedAt'];
    if (cfi.isEmpty ||
        deviceId.isEmpty ||
        progress is! num ||
        updatedAt == null) {
      return null;
    }
    return {
      'device_id': deviceId,
      'cfi': cfi,
      'progress': progress.toDouble().clamp(0, 1),
      'chapter_href': value['chapter_href'] ?? value['chapterHref'],
      'chapter_title': value['chapter_title'] ?? value['chapterTitle'],
      'updated_at': _asInt(updatedAt),
    };
  }

  static DateTime? _parseDate(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.toUtc();
  }

  static String _normalizeEndpoint(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        value,
        'endpoint',
        'A valid HTTPS service URL is required',
      );
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

int _asInt(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
