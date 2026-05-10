import 'package:flutter/material.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.isPlaying,
    required this.canResume,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
  });

  final bool isPlaying;
  final bool canResume;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filledStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final outlinedStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final playButton = FilledButton.tonalIcon(
      style: filledStyle,
      onPressed: isPlaying ? null : onPlay,
      icon: Icon(
        canResume ? Icons.play_circle_fill : Icons.play_arrow,
      ),
      label: Text(
        canResume ? 'Resume' : 'Play',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final pauseButton = OutlinedButton.icon(
      style: outlinedStyle,
      onPressed: isPlaying ? onPause : null,
      icon: const Icon(Icons.pause),
      label: const Text(
        'Pause',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final stopButton = OutlinedButton.icon(
      style: outlinedStyle,
      onPressed: onStop,
      icon: const Icon(Icons.stop),
      label: const Text(
        'Stop',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(flex: 11, child: playButton),
            const SizedBox(width: 8),
            Expanded(flex: 10, child: pauseButton),
            const SizedBox(width: 8),
            Expanded(flex: 9, child: stopButton),
          ],
        ),
      ),
    );
  }
}
