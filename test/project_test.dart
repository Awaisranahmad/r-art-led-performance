import 'package:flutter_test/flutter_test.dart';
import 'package:r_art_led_performance/ignis/ignis_converter.dart';
import 'package:r_art_led_performance/models/project.dart';

PhotoData _redPhoto(String name, int w, int h) => PhotoData(
      name: name,
      width: w,
      height: h,
      rgb888: List<int>.filled(w * h * 3, 0)
        ..setAll(0, List<int>.generate(w * h * 3, (i) => i % 3 == 0 ? 200 : 0)),
    );

void main() {
  group('RArtProject export', () {
    test('hamesha exactly 30 photos export hoti hain (firmware rule)', () {
      final project = RArtProject();
      project.slots[0] = TimelinePhoto(
        photo: _redPhoto('a', 2, 50),
        fileName: 'a.png',
      );
      final photos = project.exportPhotos();
      expect(photos.length, 30);
      expect(photos[0].width, 2);
      // Khaali slots = 1-column black.
      expect(photos[1].width, 1);
      expect(photos[1].rgb888, List<int>.filled(150, 0));
      expect(photos[29].rgb888, List<int>.filled(150, 0));

      final bytes = project.exportDataBytes();
      final widths = IgnisConverter.parseDataHWidths(bytes);
      expect(widths.length, 30);
      expect(widths[0], 2);
      expect(widths.sublist(1), List<int>.filled(29, 1));
    });

    test('export data.h text valid hai aur round-trip karta hai', () {
      final project = RArtProject();
      project.slots[0] = TimelinePhoto(
        photo: _redPhoto('a', 3, 50),
        fileName: 'a.png',
      );
      final text = project.exportDataH();
      expect(text, contains('const uint8_t PROGMEM pixels['));
      expect(text, contains('// Ignis RGB888 collection: 30 photos'));
      final bytes = IgnisConverter.parseDataHBytes(text);
      expect(bytes, project.exportDataBytes());
    });

    test('section reorder sirf usi section ke andar hota hai', () {
      final project = RArtProject();
      final a = TimelinePhoto(photo: _redPhoto('a', 1, 50), fileName: 'a');
      final b = TimelinePhoto(photo: _redPhoto('b', 1, 50), fileName: 'b');
      project.slots[0] = a;
      project.slots[1] = b;
      project.moveWithinSection(0, 0, 1);
      expect(project.slots[0], b);
      expect(project.slots[1], a);
      // Section 2 untouched.
      expect(project.slots[10], isNull);
    });
  });

  group('TimelinePhoto transforms', () {
    test('flipVertical rows ko ulta karta hai', () {
      // 1 wide x 2 tall: row0 = red, row1 = green.
      final photo = PhotoData(
        name: 't',
        width: 1,
        height: 2,
        rgb888: [255, 0, 0, 0, 255, 0],
      );
      final slot = TimelinePhoto(photo: photo, fileName: 't.png')
        ..flipVertical = true;
      final out = slot.toExportPhoto();
      // Pehle 2 rows ab green, red hain — baaqi 48 black (centered pad).
      expect(out.rgb888.sublist(0, 3), [0, 255, 0]);
      expect(out.rgb888.sublist(3, 6), [255, 0, 0]);
    });

    test('brightness scale karta hai aur clamp karta hai', () {
      final photo = PhotoData(
        name: 't',
        width: 1,
        height: 50,
        rgb888: List<int>.filled(150, 200),
      );
      final slot = TimelinePhoto(photo: photo, fileName: 't.png')
        ..brightness = 2.0;
      expect(slot.toExportPhoto().rgb888, List<int>.filled(150, 255));
      slot.brightness = 0.5;
      expect(slot.toExportPhoto().rgb888, List<int>.filled(150, 100));
    });

    test('rotate90 dimensions badalta hai', () {
      final photo = PhotoData(
        name: 't',
        width: 2,
        height: 50,
        rgb888: List<int>.filled(2 * 50 * 3, 10),
      );
      final slot = TimelinePhoto(photo: photo, fileName: 't.png')
        ..rotationSteps = 1;
      final out = slot.toExportPhoto();
      expect(out.width, 50);
      expect(out.height, 2);
      // Height adjust ke baad 50 rows — export mein pad hoga.
      expect(out.rgb888.length, 50 * 2 * 3);
    });
  });
}
