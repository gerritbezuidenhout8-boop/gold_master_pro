import 'package:flutter/material.dart';

/// Login screen — implemented in Phase 3 with Firebase Auth.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: const Center(
        child: Text('Firebase Auth arrives in Phase 3'),
      ),
    );
  }
}
