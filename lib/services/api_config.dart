/// Central configuration for the photo server connection.
///
/// Change [serverHost] when the home server gets a new LAN address.
/// Keeping the host here means the rest of the app never needs to know
/// the server's IP address.
class ApiConfig {
  /// Current home-server hostname on the local network.
  static const String serverHost = 'homelab.local';

  /// FastAPI HTTP port.
  static const int serverPort = 8000;

  /// Base URL used by all API services.
  static const String baseUrl = 'http://$serverHost:$serverPort';
}
