import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/reading_agent_sync.dart';
import 'package:anx_reader/service/ai/reading_device_identity.dart';
import 'package:anx_reader/service/sync/reading_agent_sync_service.dart';
import 'package:anx_reader/service/sync/reading_agent_sync_transport.dart';
import 'package:anx_reader/service/sync/self_hosted_progress_sync_transport.dart';
import 'package:dio/dio.dart';

/// Coordinates lifecycle/manual progress synchronization while keeping the
/// existing ReadingAgent merge and single-flight boundaries intact.
class SelfHostedProgressSyncCoordinator {
  const SelfHostedProgressSyncCoordinator();

  Future<void> synchronize() async {
    final prefs = Prefs();
    if (!prefs.selfHostedProgressSyncEnabled) return;
    final endpoint = prefs.selfHostedProgressSyncEndpoint.trim();
    final token = prefs.selfHostedProgressSyncToken.trim();
    if (endpoint.isEmpty || token.isEmpty) {
      throw StateError('Self-hosted progress sync is not configured');
    }
    final expiresAt = prefs.selfHostedProgressSyncTokenExpiresAt;
    if (expiresAt > 0 && expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      prefs.clearSelfHostedProgressSyncAccount();
      prefs.selfHostedProgressSyncEnabled = false;
      throw StateError('Self-hosted progress sync session has expired');
    }
    final deviceId = await ReadingDeviceIdentity().getOrCreate();
    final transport = SelfHostedProgressSyncTransport(
      endpoint: endpoint,
      accessToken: token,
      deviceId: deviceId,
    );
    final service = ReadingAgentSyncService(deviceId: deviceId);
    try {
      await transport.ping();
      final changes = await transport.downloadChanges(
        cursor: prefs.selfHostedProgressSyncCursor,
      );
      await service.synchronizeWithTransport(
        _PreloadedProgressSyncTransport(
          delegate: transport,
          packages: changes.packages,
        ),
      );
      // Advance only after both merge and upload complete. Replaying a page
      // after a transient failure is safe because writes are idempotent.
      prefs.selfHostedProgressSyncCursor = changes.nextCursor;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        prefs.clearSelfHostedProgressSyncAccount();
        prefs.selfHostedProgressSyncEnabled = false;
        throw StateError('Self-hosted progress sync session has expired');
      }
      rethrow;
    }
  }
}

class _PreloadedProgressSyncTransport implements ReadingAgentSyncTransport {
  const _PreloadedProgressSyncTransport({
    required this.delegate,
    required this.packages,
  });

  final SelfHostedProgressSyncTransport delegate;
  final List<ReadingAgentBookDelta> packages;

  @override
  Future<void> ping() async {}

  @override
  Future<List<ReadingAgentBookDelta>> downloadPackages(
    Iterable<String> bookKeys,
  ) async =>
      packages;

  @override
  Future<void> uploadPackages(
    Iterable<ReadingAgentBookDelta> packages,
  ) =>
      delegate.uploadPackages(packages);
}
