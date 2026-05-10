import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/file_import_service.dart';
import 'services/novel_import_controller.dart';
import 'services/novel_library_service.dart';
import 'services/reader_audio_handler.dart';
import 'services/storage_service.dart';
import 'services/theme_controller.dart';
import 'services/tts_service.dart';
import 'services/web_novel_import_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = StorageService();
  await storageService.initialize();
  final novelLibraryService = NovelLibraryService();
  final webNovelImportService = WebNovelImportService();
  final fileImportService = FileImportService();
  final themeController = ThemeController(storageService: storageService);
  await themeController.initialize();

  final ttsService = TtsService(
    storageService: storageService,
    fileImportService: fileImportService,
  );
  await ttsService.initialize();
  final novelImportController = NovelImportController(
    storageService: storageService,
    fileImportService: fileImportService,
    novelLibraryService: novelLibraryService,
    webNovelImportService: webNovelImportService,
    ttsService: ttsService,
  );
  await novelImportController.initialize();
  final audioHandler = await AudioService.init(
    builder: () => ReaderAudioHandler(
      ttsService: ttsService,
      novelImportController: novelImportController,
    ),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.textreader.voiceapp.playback',
      androidNotificationChannelName: 'DhebeVoice Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    TextReaderApp(
      themeController: themeController,
      ttsService: ttsService,
      novelImportController: novelImportController,
      audioHandler: audioHandler,
    ),
  );
}

class TextReaderApp extends StatelessWidget {
  const TextReaderApp({
    super.key,
    required this.themeController,
    required this.ttsService,
    required this.novelImportController,
    required this.audioHandler,
  });

  final ThemeController themeController;
  final TtsService ttsService;
  final NovelImportController novelImportController;
  final AudioHandler audioHandler;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider<TtsService>.value(value: ttsService),
        ChangeNotifierProvider<NovelImportController>.value(
          value: novelImportController,
        ),
        Provider<AudioHandler>.value(value: audioHandler),
      ],
      child: Consumer<ThemeController>(
        builder: (context, controller, _) {
          return MaterialApp(
            title: 'DhebeVoice',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(brightness: Brightness.light),
            darkTheme: _buildTheme(brightness: Brightness.dark),
            themeMode: controller.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}

ThemeData _buildTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: const Color(0xFF5DB0FF),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF0B0F14) : const Color(0xFFF4F8FC),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF141B22) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF141B22) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.all(20),
    ),
    sliderTheme: const SliderThemeData(
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
  );
}
