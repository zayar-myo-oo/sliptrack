import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'state.dart';
import '../database/database.dart';

Future<void> startApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repo = await Repository.open();
    final prefs = Preferences(repo, await repo.settings());
    runApp(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          preferencesProvider.overrideWithValue(prefs),
        ],
        child: const SlipTrackApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 24),
                  const Text(
                    'Secure storage is unavailable. Unlock your device and retry. Your data has not been reset.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: startApp, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
