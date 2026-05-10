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
    final playButton = FilledButton.tonalIcon(
      onPressed: isPlaying ? null : onPlay,
      icon: Icon(
        canResume ? Icons.play_circle_fill : Icons.play_arrow,
      ),
      label: Text(canResume ? 'Resume' : 'Play'),
    );
    final pauseButton = OutlinedButton.icon(
      onPressed: isPlaying ? onPause : null,
      icon: const Icon(Icons.pause),
      label: const Text('Pause'),
    );
    final stopButton = OutlinedButton.icon(
      onPressed: onStop,
      icon: const Icon(Icons.stop),
      label: const Text('Stop'),
    );

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111821),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white10),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  playButton,
                  const SizedBox(height: 12),
                  pauseButton,
                  const SizedBox(height: 12),
                  stopButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: playButton),
                const SizedBox(width: 12),
                Expanded(child: pauseButton),
                const SizedBox(width: 12),
                Expanded(child: stopButton),
              ],
            );
          },
        ),
      ),
    );
  }
}
