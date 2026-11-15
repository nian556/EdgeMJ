import 'package:flutter/material.dart';

import 'pages/manual_input_page.dart';
import 'pages/scan_page.dart';

void main() => runApp(const EdgeMjApp());

class EdgeMjApp extends StatelessWidget {
  const EdgeMjApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EdgeMJ',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

/// 首頁：下方分頁切換「拍照辨識」與「手動輸入」
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack：切換分頁時保留各頁的內容
      body: IndexedStack(
        index: _tab,
        children: const [ScanPage(), WaitCalculatorPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.photo_camera), label: '拍照辨識'),
          NavigationDestination(icon: Icon(Icons.keyboard), label: '手動輸入'),
        ],
      ),
    );
  }
}
