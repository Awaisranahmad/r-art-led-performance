import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:r_art_led_performance/ignis/ignis_converter.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('Rolandi ground truth — 1.h -> data.h', () {
    test('skull photo converts BYTE-FOR-BYTE like Rolandi\'s data.h', () {
      // Rolandi ki 1.h (skull, 61x50) + uski data.h (9160 bytes).
      final photo = IgnisConverter.parseHFile(
        _fixture('1.h.txt'),
        name: '1.h',
      );
      expect(photo.width, 61);
      expect(photo.height, 50);
      expect(photo.rgb888.length, 61 * 50 * 3);

      final produced = IgnisConverter.buildDataBytes([photo]);
      final expected =
          IgnisConverter.parseDataHBytes(_fixture('data_1photo.h.txt'));

      expect(produced.length, 9160);
      expect(expected.length, 9160);
      // Yehi asal test hai — har byte same hona chahiye.
      expect(produced, expected);
    });

    test('formatted data.h text round-trips to the same bytes', () {
      final photo = IgnisConverter.parseHFile(_fixture('1.h.txt'));
      final bytes = IgnisConverter.buildDataBytes([photo]);
      final text = IgnisConverter.formatDataH(bytes, 1);
      expect(text, contains('const uint8_t PROGMEM pixels[9160] = {'));
      expect(text, contains('// Ignis RGB888 collection: 1 photos'));
      expect(IgnisConverter.parseDataHBytes(text), bytes);
    });
  });

  group('30-photo data.h structure', () {
    test('signature + count 30 + widths parse cleanly', () {
      final bytes =
          IgnisConverter.parseDataHBytes(_fixture('data_30photos.h.txt'));
      expect(bytes.length, 245347);
      final widths = IgnisConverter.parseDataHWidths(bytes);
      expect(widths.length, 30);
      for (final w in widths) {
        expect(w, greaterThan(0));
      }
    });
  });

  group('height adjust to 50 LEDs', () {
    test('short image gets centered black padding', () {
      // 2 wide x 4 tall, har pixel R=10,G=20,B=30.
      final rgb = List<int>.filled(2 * 4 * 3, 0);
      for (var i = 0; i < rgb.length; i += 3) {
        rgb[i] = 10;
        rgb[i + 1] = 20;
        rgb[i + 2] = 30;
      }
      final adjusted = IgnisConverter.adjustHeight(rgb, 2, 4);
      expect(adjusted.length, 2 * 50 * 3);
      // missing = 46, top = 23, bottom = 23.
      for (var y = 0; y < 50; y++) {
        final row = adjusted.sublist(y * 6, y * 6 + 6);
        if (y < 23 || y >= 27) {
          expect(row, [0, 0, 0, 0, 0, 0], reason: 'row $y black');
        } else {
          expect(row, [10, 20, 30, 10, 20, 30], reason: 'row $y photo');
        }
      }
    });

    test('tall image gets cropped to the middle 50 rows', () {
      // 1 wide x 60 tall, row y ka R = y (pehchanne ke liye).
      final rgb = <int>[];
      for (var y = 0; y < 60; y++) {
        rgb.addAll([y, 0, 0]);
      }
      final adjusted = IgnisConverter.adjustHeight(rgb, 1, 60);
      expect(adjusted.length, 1 * 50 * 3);
      // startY = (60-50) ~/ 2 = 5 -> rows 5..54.
      for (var y = 0; y < 50; y++) {
        expect(adjusted[y * 3], 5 + y, reason: 'row $y');
      }
    });

    test('50-tall image is unchanged', () {
      final rgb = List<int>.generate(3 * 50 * 3, (i) => i % 256);
      expect(IgnisConverter.adjustHeight(rgb, 3, 50), rgb);
    });
  });

  group('column-major layout', () {
    test('columns come out left-to-right, top row first', () {
      // 2 wide x 50 tall. Pixel (x,y) ka R = x*100 + y, G/B = 0.
      final rgb = <int>[];
      for (var y = 0; y < 50; y++) {
        for (var x = 0; x < 2; x++) {
          rgb.addAll([x * 100 + y, 0, 0]);
        }
      }
      final colMajor = IgnisConverter.toColumnMajor(rgb, 2);
      expect(colMajor.length, 2 * 50 * 3);
      // Column 0: rows 0..49 (R = 0..49). Column 1: R = 100..149.
      for (var y = 0; y < 50; y++) {
        expect(colMajor[y * 3], y, reason: 'col 0 row $y');
        expect(colMajor[150 + y * 3], 100 + y, reason: 'col 1 row $y');
      }
    });
  });

  group('data.h format', () {
    test('header + per-photo header bytes are exact', () {
      final photo = PhotoData(
        name: 'test',
        width: 2,
        height: 50,
        rgb888: List<int>.filled(2 * 50 * 3, 7),
      );
      final bytes = IgnisConverter.buildDataBytes([photo]);
      expect(bytes.sublist(0, 7), [0x49, 0x47, 0x4E, 0x49, 0x53, 0x00, 1]);
      expect(bytes.sublist(7, 10), [0x00, 0x02, 0x00]); // width 2 BE + type
      expect(bytes.length, 7 + 3 + 2 * 50 * 3);
    });

    test('empty photo list throws', () {
      expect(() => IgnisConverter.buildDataBytes([]), throwsArgumentError);
    });
  });
}
