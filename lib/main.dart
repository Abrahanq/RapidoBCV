import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'classic_screen.dart';
import 'tasa_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const String _themeIsDarkKey = 'theme_is_dark';
  static const String _uiClassicKey = 'ui_classic';
  ThemeMode _themeMode = ThemeMode.dark;
  bool _useClassicUi = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final isDark = prefs.getBool(_themeIsDarkKey);
      if (isDark != null) {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      }
      _useClassicUi = prefs.getBool(_uiClassicKey) ?? false;
    });
  }

  Future<void> _toggleTheme(bool isCurrentlyDark) async {
    final next = isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;
    setState(() { _themeMode = next; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeIsDarkKey, next == ThemeMode.dark);
  }

  Future<void> _toggleUi() async {
    setState(() { _useClassicUi = !_useClassicUi; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_uiClassicKey, _useClassicUi);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RápidoBCV',
      debugShowCheckedModeBanner: false,
      // Español para los textos de Material (calendario, menús de copiar/pegar).
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FED)),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6FED),
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: _useClassicUi
          ? ConversorPage(onToggleTheme: _toggleTheme, onToggleUI: _toggleUi)
          : TasaScreen(onToggleTheme: _toggleTheme, onToggleUI: _toggleUi),
    );
  }
}
