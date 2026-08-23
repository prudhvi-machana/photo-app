import 'package:flutter/material.dart';

import 'screens/login_screen.dart';

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}