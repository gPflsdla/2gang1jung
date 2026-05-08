// ========================================================================
// 배리어프리(Barrier-Free) 보행자 네비게이션 — Flutter 앱
// ========================================================================
// main.dart — 앱 진입점
// ========================================================================

import 'package:flutter/material.dart';
import 'screens/map_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BarrierFreeNavApp());
}

class BarrierFreeNavApp extends StatelessWidget {
  const BarrierFreeNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '배리어프리 네비게이션',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32), // 접근성을 상징하는 그린
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      home: const MapScreen(),
    );
  }
}
