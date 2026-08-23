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

    final data = jsonDecode(response.body);
    final token = data['access_token'] as String;

    await _tokenStorage.saveToken(token);

    return token;
  }

  Future<String?> getToken() async {
    return _tokenStorage.getToken();
  }

  Future<void> logout() async {
    await _tokenStorage.clearToken();
  }
}