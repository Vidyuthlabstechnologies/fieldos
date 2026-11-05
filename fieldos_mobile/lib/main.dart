import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/app.dart';

void main() => runApp(const ProviderScope(child: AppWithMaterial()));

class AppWithMaterial extends StatelessWidget {
  const AppWithMaterial({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1B5E20),
        scaffoldBackgroundColor: const Color(0xFFF6F7F6),
      ),
      home: const App(),
    );
  }
}
