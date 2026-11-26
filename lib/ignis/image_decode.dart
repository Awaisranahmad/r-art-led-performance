/// Image files (JPG / PNG / BMP / WebP) ko RGB888 rows mein decode karo.
///
/// `image` package pure Dart hai — mobile aur web dono par chalta hai.
/// Decode hamesha top-to-bottom rows deta hai. BMP ki asal row order
/// file mein bottom-up hoti hai, lekin Rolandi ke online converter
/// (FileToCArray) ka behavior unconfirmed hai — is liye flip ka
/// toggle editor mein hai, yahan koi guess nahi lagaya gaya.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:r_art_led_performance/ignis/ignis_converter.dart';
import 'package:r_art_led_performance/models/project.dart';

Future<PhotoData> decodeImageBytes(Uint8List bytes, String name) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw FormatException('Image decode nahi hui: $name');
  }
  final rgb = <int>[];
  for (var y = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      rgb.addAll([pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()]);
    }
  }
  return PhotoData(
    name: name,
    width: decoded.width,
    height: decoded.height,
    rgb888: rgb,
  );
}

Future<TimelinePhoto> timelinePhotoFromBytes(
  Uint8List bytes,
  String fileName,
) async {
  final photo = await decodeImageBytes(bytes, fileName);
  final slot = TimelinePhoto(photo: photo, fileName: fileName);
  slot.setOriginalBytes(bytes);
  return slot;
}

/// Saved project JSON wapas load karo.
Future<RArtProject> projectFromJson(Map<String, dynamic> json) async {
  final project = RArtProject(name: json['name'] as String? ?? 'R Art Show');
  final slots = json['slots'] as List<dynamic>? ?? [];
  for (var i = 0; i < slots.length && i < RArtProject.slotCount; i++) {
    final s = slots[i];
    if (s == null) continue;
    final m = s as Map<String, dynamic>;
    final bytes = base64Decode(m['imageBase64'] as String);
    final slot = await timelinePhotoFromBytes(
      bytes,
      m['fileName'] as String? ?? 'photo_${i + 1}',
    );
    slot.durationMs = (m['durationMs'] as num?)?.toInt() ?? 3000;
    slot.flipVertical = m['flipVertical'] as bool? ?? false;
    slot.brightness = (m['brightness'] as num?)?.toDouble() ?? 1.0;
    slot.rotationSteps = (m['rotationSteps'] as num?)?.toInt() ?? 0;
    project.slots[i] = slot;
  }
  return project;
}
