import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/file_import_service.dart';
import 'services/storage_service.dart';
import 'services/tts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = StorageService();
  await storageService.initialize();

  final ttsService = TtsService(
    storageService: storageService,
    fileImportService: FileImportService(),
  );
  await ttsService.initialize();

  runApp(TextReaderApp(ttsService: ttsService));
}

class TextReaderApp extends StatelessWidget {
  const TextReaderApp({super.key, required this.ttsService});

  final TtsService ttsService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: const Color(0xFF5DB0FF),
      surface: const Color(0xFF11161C),
    );

    return ChangeNotifierProvider<TtsService>.value(
      value: ttsService,
      child: MaterialApp(
        title: 'Text Reader',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: colorScheme,
          scaffoldBackgroundColor: const Color(0xFF0B0F14),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF141B22),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF141B22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(20),
          ),
          sliderTheme: const SliderThemeData(
            showValueIndicator: ShowValueIndicator.always,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
