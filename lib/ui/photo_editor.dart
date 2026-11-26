/// Photo editor — aik slot ki settings.
///
/// Flip toggle BMP row-order correction ke liye hai: agar hardware
/// test par photo ulti dikhe to isko on karo, dobara export karo.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:r_art_led_performance/models/project.dart';

class PhotoEditorSheet extends StatefulWidget {
  const PhotoEditorSheet({
    super.key,
    required this.slot,
    required this.slotIndex,
    required this.onReplace,
    required this.onRemove,
  });

  final TimelinePhoto slot;
  final int slotIndex;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  State<PhotoEditorSheet> createState() => _PhotoEditorSheetState();
}

class _PhotoEditorSheetState extends State<PhotoEditorSheet> {
  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    slot.originalBytes,
                    width: 96,
                    height: 96,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 96,
                      height: 96,
                      child: Icon(Icons.broken_image),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot.fileName,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Photo ${widget.slotIndex + 1}  •  '
                        'Section ${widget.slotIndex ~/ 10 + 1}  •  '
                        '${slot.photo.width} x ${slot.photo.height}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Vertical flip'),
              subtitle: const Text(
                'Agar staff par photo ulti dikhe to on karo',
              ),
              value: slot.flipVertical,
              onChanged: (v) => setState(() => slot.flipVertical = v),
            ),
            ListTile(
              title: Text('Brightness: ${slot.brightness.toStringAsFixed(1)}x'),
              subtitle: Slider(
                value: slot.brightness,
                min: 0.2,
                max: 2.0,
                divisions: 18,
                label: '${slot.brightness.toStringAsFixed(1)}x',
                onChanged: (v) => setState(() => slot.brightness = v),
              ),
            ),
            ListTile(
              title: const Text('Rotate'),
              subtitle: Text('${slot.rotationSteps * 90}° clockwise'),
              trailing: IconButton(
                tooltip: '90° ghumao',
                icon: const Icon(Icons.rotate_right),
                onPressed: () => setState(
                  () => slot.rotationSteps = (slot.rotationSteps + 1) % 4,
                ),
              ),
            ),
            ListTile(
              title: const Text('Duration'),
              subtitle: Text(
                '${(slot.durationMs / 1000).toStringAsFixed(1)} seconds per photo',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Kam karo',
                    icon: const Icon(Icons.remove),
                    onPressed: slot.durationMs > 500
                        ? () => setState(() => slot.durationMs -= 500)
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Zyada karo',
                    icon: const Icon(Icons.add),
                    onPressed: slot.durationMs < 10000
                        ? () => setState(() => slot.durationMs += 500)
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Replace'),
                  onPressed: widget.onReplace,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                  onPressed: widget.onRemove,
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bytes se thumbnail banane ka chhota helper (memory image ke liye).
Widget photoThumbnail(Uint8List bytes, {double size = 56}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.broken_image),
      ),
    ),
  );
}
