import 'package:flutter/material.dart';

import 'src/converter_page.dart';

void main() => runApp(const ImageToPdfApp());

class ImageToPdfApp extends StatelessWidget {
  const ImageToPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'REY Converter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3859C7)),
        useMaterial3: true,
      ),
      home: const ConverterPage(),
    );
  }
}
