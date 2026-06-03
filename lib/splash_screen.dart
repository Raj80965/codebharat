import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'main.dart'; // Your home page
import 'pages/login_page.dart'; // Login page
import 'services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();

    // 1️⃣ Animation setup
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    // 2️⃣ Play welcome sound after a short delay
    Future.delayed(const Duration(milliseconds: 300), () async {
      await _playWelcomeSound();
    });
  }

  Future<void> _playWelcomeSound() async {
    try {
      print("🎵 Playing welcome.mp3 (6 sec)...");
      await _player.play(AssetSource('sounds/welcome.mp3'));

      // Navigate after sound completes
      _player.onPlayerComplete.listen((event) {
        print("🎶 Sound completed, navigating to home...");
        _navigateToHome();
      });
    } catch (e) {
      print("⚠️ Error playing sound: $e");
      // Fallback: navigate after 6 sec if sound fails
      Timer(const Duration(seconds: 3), _navigateToHome);
    }
  }

  void _navigateToHome() {
    if (!mounted) return;
    // Always navigate to login page first
    // User needs to explicitly log in even if they have registered
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    _player.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple.shade700,
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.language_rounded,
                  color: Colors.white, size: 100),
              const SizedBox(height: 20),
              const Text(
                "CodeBharat 🇮🇳",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Smart Indian Transliteration & Translation",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
