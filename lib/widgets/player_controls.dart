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
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111821),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: isPlaying ? null : onPlay,
                icon: Icon(
                  canResume ? Icons.play_circle_fill : Icons.play_arrow,
                ),
                label: Text(canResume ? 'Resume' : 'Play'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isPlaying ? onPause : null,
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
