import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'token_storage.dart';

class AuthService {
  final String baseUrl = ApiConfig.baseUrl;
  final TokenStorage _tokenStorage = TokenStorage();

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Invalid username or password');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;

    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    return accessToken;
  }

  Future<String?> getToken() async => _tokenStorage.getToken();

  Future<String?> getRefreshToken() async => _tokenStorage.getRefreshToken();

  Future<String?> refreshAccessToken() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;

    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String;
    final newRefreshToken = data['refresh_token'] as String? ?? refreshToken;

    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: newRefreshToken,
    );
    return accessToken;
  }

  Future<void> logout() async => _tokenStorage.clearToken();
}
