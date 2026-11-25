import 'package:flutter/material.dart';
import 'ui/home_page.dart';

void main() => runApp(const SFListApp());

class SFListApp extends StatelessWidget {
  const SFListApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SFList',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF8E7CF0),
        inputDecorationTheme: const InputDecorationTheme(isDense: true),
      ),
      home: const HomePage(),
    );
  }
}