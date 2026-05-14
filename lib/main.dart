import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

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

const _playbackChannelId = 'com.dhebe.dhebevoice.playback.v5';
const _systemChannel = MethodChannel('com.dhebe.dhebevoice/system');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  _AppServices? _services;
  Object? _error;
  bool _isBootstrapping = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_isBootstrapping) {
      return;
    }

    setState(() {
      _isBootstrapping = true;
      _error = null;
    });

    try {
      final services = await _initializeAppServices();
      if (!mounted) {
        return;
      }

      setState(() {
        _services = services;
        _isBootstrapping = false;
      });
      unawaited(_ensureAndroidNotificationPermission());
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
        _isBootstrapping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services != null) {
      return TextReaderApp(
        themeController: services.themeController,
        ttsService: services.ttsService,
        novelImportController: services.novelImportController,
        audioHandler: services.audioHandler,
      );
    }

    return MaterialApp(
      title: 'DhebeVoice',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(brightness: Brightness.light),
      darkTheme: _buildTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: _BootstrapScreen(
        error: _error,
        isLoading: _isBootstrapping,
        onRetry: _bootstrap,
      ),
    );
  }
}

Future<_AppServices> _initializeAppServices() async {
  await _ensureAndroidPlaybackChannel();

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
      androidNotificationChannelId: _playbackChannelId,
      androidNotificationChannelName: 'DhebeVoice Playback',
      androidNotificationChannelDescription:
          'Playback controls for DhebeVoice reading sessions',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  return _AppServices(
    themeController: themeController,
    ttsService: ttsService,
    novelImportController: novelImportController,
    audioHandler: audioHandler,
  );
}

Future<void> _ensureAndroidPlaybackChannel() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    await _systemChannel.invokeMethod<void>(
      'ensurePlaybackChannel',
      <String, dynamic>{
        'id': _playbackChannelId,
        'name': 'DhebeVoice Playback',
        'description': 'Playback controls for DhebeVoice reading sessions',
      },
    );
  } on PlatformException {
    // The audio_service plugin can still create its own fallback channel.
  }
}

Future<void> _ensureAndroidNotificationPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    await _systemChannel.invokeMethod<bool>('ensureNotificationPermission');
  } on PlatformException {
    // Playback can still continue even if the permission prompt fails.
  }
}

class _AppServices {
  const _AppServices({
    required this.themeController,
    required this.ttsService,
    required this.novelImportController,
    required this.audioHandler,
  });

  final ThemeController themeController;
  final TtsService ttsService;
  final NovelImportController novelImportController;
  final AudioHandler audioHandler;
}

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen({
    required this.error,
    required this.isLoading,
    required this.onRetry,
  });

  final Object? error;
  final bool isLoading;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasError = error != null;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.92),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.record_voice_over_rounded,
                            size: 34,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'DhebeVoice',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasError
                              ? 'The app could not finish loading.'
                              : 'Preparing your reader and playback services…',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (hasError) ...[
                          Text(
                            error.toString(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: isLoading ? null : () => unawaited(onRetry()),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ] else ...[
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'This screen should appear right away while the app finishes loading.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  final scaffoldColor =
      isDark ? const Color(0xFF071019) : const Color(0xFFEAF1F8);
  final cardColor = isDark ? const Color(0xFF182430) : Colors.white;
  final inputFillColor = isDark ? const Color(0xFF1C2936) : Colors.white;
  final seedScheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: const Color(0xFF5DB0FF),
  );
  final colorScheme = isDark
      ? seedScheme.copyWith(
          primary: const Color(0xFFA8CEFF),
          onPrimary: const Color(0xFF002B5F),
          primaryContainer: const Color(0xFF173E73),
          onPrimaryContainer: const Color(0xFFE0ECFF),
          secondary: const Color(0xFF8ED7E6),
          onSecondary: const Color(0xFF003640),
          surface: const Color(0xFF141B22),
          onSurface: const Color(0xFFF2F6FC),
          onSurfaceVariant: const Color(0xFFC7D2E2),
          outline: const Color(0xFF8D9AAF),
          outlineVariant: const Color(0xFF3A4658),
          error: const Color(0xFFFFB4AB),
          onError: const Color(0xFF690005),
        )
      : seedScheme.copyWith(
          primary: const Color(0xFF0E61C9),
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFDCEAFF),
          onPrimaryContainer: const Color(0xFF08264C),
          secondary: const Color(0xFF006B79),
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: const Color(0xFF121A27),
          onSurfaceVariant: const Color(0xFF3A485B),
          outline: const Color(0xFF66768B),
          outlineVariant: const Color(0xFFD0D8E4),
          error: const Color(0xFFB3261E),
          onError: Colors.white,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldColor,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: isDark ? 0 : 2,
      shadowColor: isDark
          ? Colors.transparent
          : const Color(0xFF91A6C6).withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark
              ? colorScheme.outlineVariant
              : colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFillColor,
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(
          color: isDark
              ? colorScheme.outlineVariant
              : colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.all(20),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: isDark
              ? colorScheme.outlineVariant
              : colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cardColor,
      modalBackgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerColor: colorScheme.outlineVariant,
    sliderTheme: const SliderThemeData(
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
  );
}
