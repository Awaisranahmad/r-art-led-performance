/// On-screen POV preview — photo hawa mein kaise banegi, ye dikhata hai.
///
/// Asal staff par LEDs aik column aik waqt mein jalti hain aur staff
/// ghumta hai; aankh columns ko jor kar poori photo dekh leti hai
/// (persistence of vision). Ye widget wahi simulate karta hai:
/// aik roshan LED column left-to-right sweep karta hai, aur peeche
/// guzre columns halke hote hue "fade" hote hain.
library;

import 'package:flutter/material.dart';
import 'package:r_art_led_performance/ignis/ignis_converter.dart';

class PovPreview extends StatefulWidget {
  const PovPreview({
    super.key,
    required this.photo,
    this.columnMs = 40,
  });

  /// Export-ready photo (height 50, row-major).
  final PhotoData photo;

  /// Har column par kitne ms (sweep speed).
  final int columnMs;

  @override
  State<PovPreview> createState() => _PovPreviewState();
}

class _PovPreviewState extends State<PovPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.photo.width * widget.columnMs),
    )..repeat();
  }

  @override
  void didUpdateWidget(PovPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo ||
        oldWidget.columnMs != widget.columnMs) {
      _controller.duration =
          Duration(milliseconds: widget.photo.width * widget.columnMs);
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: photo.width / IgnisConverter.ledCount,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _PovPainter(
                  photo: photo,
                  progress: _controller.value,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: _playing ? 'Roko' : 'Chalao',
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() {
                  _playing = !_playing;
                  if (_playing) {
                    _controller.repeat();
                  } else {
                    _controller.stop();
                  }
                });
              },
            ),
            Text(
              '${photo.width} columns  •  '
              '${(photo.width * widget.columnMs / 1000).toStringAsFixed(1)}s per sweep',
            ),
          ],
        ),
      ],
    );
  }
}

class _PovPainter extends CustomPainter {
  _PovPainter({required this.photo, required this.progress});

  final PhotoData photo;
  final double progress;

  // Kitne peeche tak ke columns dikhein (persistence trail).
  static const int trailColumns = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final w = photo.width;
    final cellW = size.width / w;
    final cellH = size.height / IgnisConverter.ledCount;
    final currentCol = (progress * w).floor().clamp(0, w - 1);

    // Background.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black,
    );

    // Guzre hue columns — purane halke (persistence).
    for (var col = 0; col <= currentCol; col++) {
      final age = currentCol - col;
      final alpha = age >= trailColumns
          ? 0.0
          : 1.0 - (age / trailColumns) * 0.85;
      if (alpha <= 0.02) continue;
      for (var y = 0; y < IgnisConverter.ledCount; y++) {
        final src = (y * w + col) * 3;
        final r = photo.rgb888[src];
        final g = photo.rgb888[src + 1];
        final b = photo.rgb888[src + 2];
        if (r == 0 && g == 0 && b == 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * cellW, y * cellH, cellW + 0.5, cellH + 0.5),
          Paint()
            ..color = Color.fromARGB(
              (alpha * 255).round(),
              r,
              g,
              b,
            ),
        );
      }
    }

    // Chalti hui LED column — poori roshan.
    final barPaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawRect(
      Rect.fromLTWH(currentCol * cellW, 0, cellW * 1.6, size.height),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(_PovPainter old) =>
      old.progress != progress || old.photo != photo;
}
