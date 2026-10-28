import 'package:flutter/material.dart';

import 'home/home_page.dart';
import 'theme.dart';

void main() => runApp(const ParkdayApp());

class ParkdayApp extends StatelessWidget {
  const ParkdayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parkday',
      debugShowCheckedModeBanner: false,
      theme: Pd.theme(),
      home: const HomePage(),
    );
  }
}
