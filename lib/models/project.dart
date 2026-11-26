/// Project model — 30 slots, 3 sections x 10 photos.
///
/// Firmware (sketch_nov23a.ino) ka structure:
///   - Section 1 = photos 1-10, Section 2 = 11-20, Section 3 = 21-30.
///   - Har section UP/DOWN button se select hoti hai, START se chalti hai.
///   - Firmware ko EXACTLY 30 photos chahiye (PHOTO_COUNT 30).
///
/// Is liye export hamesha 30 entries likhta hai — khaali slot
/// 1-column kaale photo ke tor par export hota hai (firmware-valid).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:r_art_led_performance/ignis/ignis_converter.dart';
import 'package:r_art_led_performance/ignis/photo_transforms.dart';

class TimelinePhoto {
  TimelinePhoto({
    required this.photo,
    required this.fileName,
    this.durationMs = 3000,
    this.flipVertical = false,
    this.brightness = 1.0,
    this.rotationSteps = 0,
  });

  /// Decoded photo (original size, RGB888 row-major).
  final PhotoData photo;

  /// Original file ka naam (display ke liye).
  final String fileName;

  /// Is photo ki display duration (firmware default 3000ms).
  int durationMs;

  /// BMP row-order correction (hardware test ke baad set karo).
  bool flipVertical;

  /// 0.2 .. 2.0 (1.0 = normal).
  double brightness;

  /// 90-degree clockwise steps (0..3).
  int rotationSteps;

  /// Export-ready PhotoData: rotation + flip + brightness lagakar.
  PhotoData toExportPhoto() {
    var current = photo;
    for (var i = 0; i < rotationSteps % 4; i++) {
      current = PhotoTransforms.rotate90(current);
    }
    var rgb = current.rgb888;
    if (flipVertical) {
      rgb = PhotoTransforms.flipVertical(rgb, current.width, current.height);
    }
    rgb = PhotoTransforms.brightness(rgb, brightness);
    return PhotoData(
      name: current.name,
      width: current.width,
      height: current.height,
      rgb888: rgb,
    );
  }

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'durationMs': durationMs,
        'flipVertical': flipVertical,
        'brightness': brightness,
        'rotationSteps': rotationSteps,
        // Original image bytes (JPG/PNG/BMP/WebP) — load par dobara decode.
        'imageBase64': base64Encode(_originalBytes),
      };

  /// Original encoded image bytes (decode ke waqt save kiye gaye).
  Uint8List _originalBytes = Uint8List(0);

  void setOriginalBytes(Uint8List bytes) => _originalBytes = bytes;
  Uint8List get originalBytes => _originalBytes;
}

class RArtProject {
  RArtProject({this.name = 'R Art Show'});

  static const int slotCount = 30;
  static const int sectionSize = 10;
  static const int sectionCount = 3;

  String name;

  /// 30 slots — null = khaali. (Growable list — reorder ke liye.)
  final List<TimelinePhoto?> slots =
      List<TimelinePhoto?>.generate(slotCount, (_) => null);

  int get filledCount => slots.where((s) => s != null).length;

  List<TimelinePhoto?> sectionSlots(int section) => slots.sublist(
        section * sectionSize,
        (section + 1) * sectionSize,
      );

  /// Section ke andar item ko move karo.
  ///
  /// newIndex pehle se adjusted hota hai (ReorderableListView ka
  /// onReorderItem removed item ko gin kar deta hai) — yahan koi
  /// aur adjustment nahi.
  void moveWithinSection(int section, int oldIndex, int newIndex) {
    final start = section * sectionSize;
    final item = slots.removeAt(start + oldIndex);
    slots.insert(start + newIndex, item);
  }

  /// Export ke liye 30 PhotoData — khaali slot = 1-column black.
  List<PhotoData> exportPhotos() {
    return List<PhotoData>.generate(slotCount, (i) {
      final slot = slots[i];
      if (slot == null) {
        return PhotoData.black(name: 'empty_${i + 1}');
      }
      return slot.toExportPhoto();
    });
  }

  /// Poori data.h file (text) banao.
  String exportDataH() {
    final photos = exportPhotos();
    final bytes = IgnisConverter.buildDataBytes(photos);
    return IgnisConverter.formatDataH(bytes, photos.length);
  }

  /// Export bytes (validation ke liye).
  List<int> exportDataBytes() =>
      IgnisConverter.buildDataBytes(exportPhotos());

  Map<String, dynamic> toJson() => {
        'name': name,
        'slots': slots.map((s) => s?.toJson()).toList(),
      };
}
