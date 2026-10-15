import 'package:flutter/material.dart';
import 'package:vn_editor/vn_editor.dart';

import 'playback_example.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VN Editor SDK Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF57D39B)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF57D39B),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ExampleHome(),
      routes: {'/playback': (_) => const PlaybackExample()},
    );
  }
}

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  static final EditorProject _project = EditorProject.empty(
    id: 'Portrait story',
    width: 1080,
    height: 1920,
    frameRate: 30,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VN Editor SDK')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'A native-first editor package',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This example consumes vn_editor exactly as a host application would.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => VnEditor(project: _project),
                      ),
                    ),
                    icon: const Icon(Icons.movie_creation_outlined),
                    label: const Text('Open editor'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const PlaybackExample(),
                      ),
                    ),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Play sample video'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
