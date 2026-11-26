import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:r_art_led_performance/ignis/ignis_converter.dart';
import 'package:r_art_led_performance/ignis/image_decode.dart';
import 'package:r_art_led_performance/models/project.dart';
import 'package:r_art_led_performance/ui/photo_editor.dart';
import 'package:r_art_led_performance/ui/pov_preview.dart';

void main() {
  runApp(const RArtApp());
}

class RArtApp extends StatelessWidget {
  const RArtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'R Art LED Performance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RArtProject _project = RArtProject();

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickPhoto(int slotIndex) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    try {
      final slot = await timelinePhotoFromBytes(
        Uint8List.fromList(bytes),
        file.name,
      );
      setState(() => _project.slots[slotIndex] = slot);
    } catch (e) {
      _snack('Photo decode nahi hui: $e');
    }
  }

  void _openEditor(int slotIndex) {
    final slot = _project.slots[slotIndex];
    if (slot == null) {
      _pickPhoto(slotIndex);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PhotoEditorSheet(
        slot: slot,
        slotIndex: slotIndex,
        onReplace: () {
          Navigator.of(context).pop();
          _pickPhoto(slotIndex);
        },
        onRemove: () {
          setState(() => _project.slots[slotIndex] = null);
          Navigator.of(context).pop();
        },
      ),
    ).then((_) => setState(() {}));
  }

  Future<void> _saveProject() async {
    final json = jsonEncode(_project.toJson());
    await FilePicker.saveFile(
      dialogTitle: 'Project save karo',
      fileName: 'r-art-show.json',
      bytes: utf8.encode(json),
    );
    // Web par saveFile null Uri deta hai — download phir bhi hota hai.
    _snack('Project save ho gaya.');
  }

  Future<void> _openProject() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    try {
      final loaded = await projectFromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
      setState(() {
        _project.name = loaded.name;
        for (var i = 0; i < RArtProject.slotCount; i++) {
          _project.slots[i] = loaded.slots[i];
        }
      });
      _snack('Project khul gaya (${loaded.filledCount} photos).');
    } catch (e) {
      _snack('Project load nahi hua: $e');
    }
  }

  Future<void> _export() async {
    if (_project.filledCount == 0) {
      _snack('Pehle koi photo add karo.');
      return;
    }
    final bytes = _project.exportDataBytes();
    final widths = IgnisConverter.parseDataHWidths(bytes);
    final empty = RArtProject.slotCount - _project.filledCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export data.h'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photos: ${_project.filledCount} bhari, $empty khaali'),
            Text('Total bytes: ${bytes.length}'),
            Text('Widths: ${widths.join(', ')}'),
            const SizedBox(height: 8),
            const Text(
              'Khaali slots 1-column kaale photo ke tor par export '
              'honge — firmware ko exactly 30 photos chahiye.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Ye file Arduino mein flash karni hai (data.h replace karo).',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save data.h'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final text = _project.exportDataH();
    await FilePicker.saveFile(
      dialogTitle: 'data.h save karo',
      fileName: 'data.h',
      bytes: utf8.encode(text),
    );
    _snack('data.h export ho gaya (${bytes.length} bytes).');
  }

  void _openPreview() {
    if (_project.filledCount == 0) {
      _snack('Pehle koi photo add karo.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreviewScreen(project: _project),
      ),
    );
  }

  Widget _slotTile(int index) {
    final slot = _project.slots[index];
    return ListTile(
      key: ValueKey('slot_$index'),
      leading: slot == null
          ? const CircleAvatar(child: Icon(Icons.add))
          : photoThumbnail(slot.originalBytes),
      title: Text(
        slot?.fileName ?? 'Khaali slot ${index + 1}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: slot == null
          ? const Text('Tap karo — photo add karo')
          : Text(
              '${slot.photo.width} x ${slot.photo.height}  •  '
              '${(slot.durationMs / 1000).toStringAsFixed(1)}s'
              '${slot.flipVertical ? '  •  flipped' : ''}',
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.drag_handle),
          if (slot != null)
            IconButton(
              tooltip: 'Hatao',
              icon: const Icon(Icons.close),
              onPressed: () =>
                  setState(() => _project.slots[index] = null),
            ),
        ],
      ),
      onTap: () => _openEditor(index),
    );
  }

  Widget _sectionCard(int section) {
    final filled =
        _project.sectionSlots(section).where((s) => s != null).length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Section ${section + 1}  •  Photos ${section * 10 + 1}–${(section + 1) * 10}  •  $filled/10',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: RArtProject.sectionSize,
            itemBuilder: (context, i) =>
                _slotTile(section * RArtProject.sectionSize + i),
            onReorderItem: (oldIndex, newIndex) {
              setState(
                () => _project.moveWithinSection(section, oldIndex, newIndex),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'R Art',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            Text(
              'LED Performance  •  ${_project.filledCount}/30 photos',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Project kholo',
            icon: const Icon(Icons.folder_open),
            onPressed: _openProject,
          ),
          IconButton(
            tooltip: 'Project save karo',
            icon: const Icon(Icons.save),
            onPressed: _saveProject,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Photo add karo, order set karo, preview dekho, '
                'phir data.h export karo — firmware mein flash karne ke liye.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            _sectionCard(0),
            _sectionCard(1),
            _sectionCard(2),
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Preview'),
              onPressed: _openPreview,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.upload),
              label: const Text('Export data.h'),
              onPressed: _export,
            ),
          ],
        ),
      ),
    );
  }
}

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.project});

  final RArtProject project;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  int _selectedSlot = 0;
  double _speedMs = 40;

  List<int> get _filledSlots => [
        for (var i = 0; i < RArtProject.slotCount; i++)
          if (widget.project.slots[i] != null) i,
      ];

  @override
  void initState() {
    super.initState();
    _selectedSlot = _filledSlots.first;
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.project.slots[_selectedSlot]!;
    final exportPhoto = slot.toExportPhoto();
    return Scaffold(
      appBar: AppBar(title: const Text('POV Preview')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: _filledSlots.map((i) {
                return ChoiceChip(
                  label: Text('${i + 1}'),
                  selected: i == _selectedSlot,
                  onSelected: (_) => setState(() => _selectedSlot = i),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              slot.fileName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${exportPhoto.width} columns x 50 LEDs  •  '
              'duration ${(slot.durationMs / 1000).toStringAsFixed(1)}s',
            ),
            const SizedBox(height: 16),
            PovPreview(
              photo: exportPhoto,
              columnMs: _speedMs.round(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Speed'),
                Expanded(
                  child: Slider(
                    value: _speedMs,
                    min: 10,
                    max: 100,
                    divisions: 9,
                    label: '${_speedMs.round()} ms/col',
                    onChanged: (v) => setState(() => _speedMs = v),
                  ),
                ),
                Text('${_speedMs.round()} ms'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Ye simulation hai — asal staff par image tab banti hai '
              'jab LEDs spin ke sath column-by-column jalti hain. '
              'Agar photo ulti dikhe to editor mein Vertical flip on karo.',
            ),
          ],
        ),
      ),
    );
  }
}
