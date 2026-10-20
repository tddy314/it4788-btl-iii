import '../core/config/app_config.dart';
import '../core/media/media_upload_service.dart';
import '../core/network/api_client.dart';
import '../core/network/connection_monitor.dart';
import '../core/storage/json_cache.dart';
import '../core/storage/draft_store.dart';
import '../core/storage/key_value_store.dart';
import '../core/storage/session_store.dart';

class AppDependencies {
  AppDependencies({
    required this.config,
    required this.session,
    required this.connection,
    required this.cache,
    required this.api,
    required this.drafts,
  }) : mediaUpload = MediaUploadService(api);
  final AppConfig config;
  final SessionStore session;
  final ConnectionMonitor connection;
  final JsonCache cache;
  final ApiClient api;
  final MediaUploadService mediaUpload;
  final DraftStore drafts;

  static Future<AppDependencies> create() async {
    final config = AppConfig();
    final secureStorage = SecureKeyValueStore();
    final session = SessionStore(secureStorage);
    final connection = DeviceConnectionMonitor();
    try {
      await session.restore();
      await connection.start();
      final api = ApiClient(
        config: config,
        session: session,
        connection: connection,
      );
      return AppDependencies(
        config: config,
        session: session,
        connection: connection,
        cache: JsonCache(PreferencesKeyValueStore()),
        drafts: DraftStore(secureStorage),
        api: api,
      );
    } catch (_) {
      session.dispose();
      connection.dispose();
      rethrow;
    }
  }

  void dispose() {
    api.close();
    session.dispose();
    connection.dispose();
  }
}
