import 'package:flutter/material.dart';

import 'screens/albums_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/transfer_manager.dart';
import 'widgets/transfer_indicator.dart';

void main() {
  runApp(const PhotoStorageApp());
}

class PhotoStorageApp extends StatelessWidget {
  const PhotoStorageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Photo Storage',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: TransferIndicator())),
          ],
        );
      },
      home: const StartupScreen(),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await _authService.getToken();

    if (token == null || token.isEmpty) {
      _showLogin();
      return;
    }

    try {
      _apiService.setToken(token);
      await _apiService.getCurrentUser();
      await TransferManager.instance.initialize();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AlbumsScreen(token: token)),
      );
    } catch (_) {
      await _authService.logout();
      _showLogin();
    }
  }

  void _showLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
