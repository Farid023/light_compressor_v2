import 'package:flutter/material.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';

import 'batch_compress_view.dart';
import 'single_compress_view.dart';

void main() => runApp(const MyApp());

/// Root widget of the example app.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LightCompressor',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF344772)),
        ),
        home: const HomeScreen(),
      );
}

/// Home screen with two tabs: single-video and batch compression.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LightCompressor _compressor = LightCompressor();

  Future<void> _clearCache() async {
    await _compressor.clearCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cache cleared')),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('LightCompressor v2'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Clear cache',
                onPressed: _clearCache,
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.movie_outlined), text: 'Single'),
                Tab(icon: Icon(Icons.video_library_outlined), text: 'Batch'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              SingleCompressView(compressor: _compressor),
              BatchCompressView(compressor: _compressor),
            ],
          ),
        ),
      );
}
