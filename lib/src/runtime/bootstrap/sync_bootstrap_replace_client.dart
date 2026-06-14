import '../../protocol/sync_bootstrap_replace_request.dart';
import '../../protocol/sync_bootstrap_replace_response.dart';

/// Host-provided client for the bootstrap-replace endpoint.
///
/// Implementations are backend-specific (e.g. Supabase function, HTTP POST).
/// The package only defines the request/response shape.
abstract interface class SyncBootstrapReplaceClient {
  /// Sends [request] to the bootstrap-replace endpoint and returns the
  /// server response.
  Future<SyncBootstrapReplaceResponse> replace(SyncBootstrapReplaceRequest request);
}
