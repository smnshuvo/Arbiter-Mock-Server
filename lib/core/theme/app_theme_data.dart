import 'package:flutter/material.dart';

final lightTheme = ThemeData(
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    centerTitle: true,
    elevation: 2,
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.orange,
    primary: Colors.deepOrange,
  ),
  canvasColor: Colors.grey[100],
  // mostly use for json viewer
  highlightColor: Colors.blue.shade50,
);

final darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  appBarTheme: const AppBarTheme(
    centerTitle: true,
    elevation: 2,
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    color: Colors.grey.shade900,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
  colorScheme: const ColorScheme.dark(),
  canvasColor: const Color(0xFF1e1e1e),
  highlightColor: Colors.deepPurple.shade900,
);
