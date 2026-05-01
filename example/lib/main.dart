import 'package:flutter/material.dart';
import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindowBootstrap.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: const Center(
          child: DesktopWindowTitlebarSafeArea(
            child: Text('desktop_window_bootstrap example'),
          ),
        ),
      ),
    );
  }
}
