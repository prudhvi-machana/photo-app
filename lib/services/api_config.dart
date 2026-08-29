/// Central configuration for the photo server connection.
///
/// Change [serverHost] when the home server gets a new LAN address.
/// Keeping the host here means the rest of the app never needs to know
/// the server's IP address.
class ApiConfig {
  /// IPv4 address of the home server on the local network.
  ///
  /// We intentionally use IPv4 here because Android may resolve
  /// homelab.local to an IPv6 link-local address, which is unreliable for
  /// long-running background uploads.
  static const String serverHost = '10.14.16.253';

  /// FastAPI HTTP port.
  static const int serverPort = 8000;

  /// Temporary direct video URL used only for playback performance testing.
  ///
  /// This points to the seek-optimized test file served by the temporary
  /// HTTP server on port 8081. Set this to null to use the normal
  /// authenticated photo endpoint.
  static const String? playbackTestUrl =
      'http://$serverHost:8081/playback_seek_test.mp4';

  /// Base URL used by all API services.
  static const String baseUrl = 'http://$serverHost:$serverPort';
}
