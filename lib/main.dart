import 'package:flutter/material.dart';

import 'spiral_debug_screen.dart';
import 'splash_screen.dart';

void main() {
  runApp(const CloudSpiralApp());
}

class CloudSpiralApp extends StatelessWidget {
  const CloudSpiralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloud spiral playground',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const _EntryScreen(),
    );
  }
}

/// Lets you jump between the splash-screen demo and the raw vortex-tuning
/// playground without needing separate build targets.
class _EntryScreen extends StatelessWidget {
  const _EntryScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16161C),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SplashDemoScreen()),
              ),
              child: const Text('Splash screen demo'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SpiralDebugScreen()),
              ),
              child: const Text('Vortex tuning playground'),
            ),
          ],
        ),
      ),
    );
  }
}
