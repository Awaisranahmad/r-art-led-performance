/// R Art LED Performance — Ignis converter (pure Dart).
///
/// Rolandi ke apne Python script `batch_rgb888_to_ignis.py` ka exact port.
/// Format mein koi "improvement" nahi — jo script karta hai, yehi karta hai,
/// taake hamari data.h uski data.h se byte-for-byte mile.
///
/// Pipeline (Python script ke mutabiq):
///   1. Input: aik photo ke RGB888 bytes, row-major (width x height x 3).
///   2. Height ko exactly 50 LEDs par adjust karo:
///      - height < 50: kaale (black) rows add karo, centered
///        (top = missing ~/ 2, bottom = baaqi).
///      - height > 50: beech ki 50 rows crop karo.
///   3. Row-major -> column-major: har column x ke liye, har row y
///      (0..49) ke 3 bytes. Firmware column-by-column chalata hai.
///   4. Output data.h bytes:
///      "IGNIS" signature (0x49 0x47 0x4E 0x49 0x53 0x00)
///      + photo count (1 byte)
///      + har photo: width 2 bytes big-endian + 0x00 type byte
///        + column-major RGB bytes.
///
/// Firmware (sketch_nov23a.ino) ke mutabiq:
///   - LED 0 = row 0 (image ki pehli row).
///   - Har column 2000us, har photo 3000ms.
///   - Firmware ko EXACTLY 30 photos chahiye (PHOTO_COUNT 30) —
///     export layer khaali slots ko 1-column kaale photo se bharta hai.
library;

/// Aik photo — RGB888 bytes, row-major (pehli row = image ka top).
class PhotoData {
  PhotoData({
    required this.name,
    required this.width,
    required this.height,
    required this.rgb888,
  }) : assert(rgb888.length == width * height * 3,
            'rgb888 length must be width * height * 3');

  final String name;

  /// Photo ki chaudai (columns ki tadaad).
  final int width;

  /// Photo ki unchai (rows ki tadaad).
  final int height;

  /// Row-major RGB bytes: (y * width + x) * 3 par pixel (x, y) ka R.
  final List<int> rgb888;

  /// Sirf kaale pixels wali photo (khaali slot ke liye export mein).
  factory PhotoData.black({required String name, int width = 1}) {
    return PhotoData(
      name: name,
      width: width,
      height: IgnisConverter.ledCount,
      rgb888: List<int>.filled(width * IgnisConverter.ledCount * 3, 0),
    );
  }
}

class IgnisConverter {
  static const List<int> signature = [0x49, 0x47, 0x4E, 0x49, 0x53, 0x00];
  static const int ledCount = 50;

  /// Height ko exactly 50 rows par adjust karo (Python jaisa).
  ///
  /// Chhoti ho to kaale rows centered add karo, bari ho to beech
  /// ki 50 rows crop karo. Returns naya row-major list (height 50).
  static List<int> adjustHeight(
    List<int> rowMajor,
    int width,
    int height,
  ) {
    if (height == ledCount) return List<int>.from(rowMajor);

    if (height < ledCount) {
      final missing = ledCount - height;
      final top = missing ~/ 2;
      final padded = <int>[];
      for (var y = 0; y < ledCount; y++) {
        final sourceY = y - top;
        if (sourceY < 0 || sourceY >= height) {
          padded.addAll(List<int>.filled(width * 3, 0));
        } else {
          final start = sourceY * width * 3;
          padded.addAll(rowMajor.sublist(start, start + width * 3));
        }
      }
      return padded;
    }

    // height > 50: beech ki 50 rows.
    final startY = (height - ledCount) ~/ 2;
    final start = startY * width * 3;
    return rowMajor.sublist(start, start + ledCount * width * 3);
  }

  /// Row-major (height 50) -> column-major.
  ///
  /// Har column x ke liye, rows y = 0..49 ke 3 bytes.
  /// Firmware: column c, LED i = bytes[c * 150 + i * 3].
  static List<int> toColumnMajor(List<int> rowMajor50, int width) {
    final columnMajor = <int>[];
    for (var x = 0; x < width; x++) {
      for (var y = 0; y < ledCount; y++) {
        final start = (y * width + x) * 3;
        columnMajor.addAll(rowMajor50.sublist(start, start + 3));
      }
    }
    return columnMajor;
  }

  /// Aik photo ko export-ready bytes mein badlo
  /// (height adjust + column-major).
  static List<int> photoToColumnMajor(PhotoData photo) {
    final adjusted = adjustHeight(photo.rgb888, photo.width, photo.height);
    return toColumnMajor(adjusted, photo.width);
  }

  /// Photos ki list se poori data.h byte array banao.
  ///
  /// Har photo ki height yahan adjust hoti hai (50). Count = list ki
  /// length (1..255). Firmware ko 30 chahiye — wo export layer ki
  /// zimmedari hai (khaali slots black se bharna).
  static List<int> buildDataBytes(List<PhotoData> photos) {
    if (photos.isEmpty || photos.length > 255) {
      throw ArgumentError('Supply 1 to 255 photos.');
    }
    final allBytes = <int>[...signature, photos.length];
    for (final photo in photos) {
      final columnMajor = photoToColumnMajor(photo);
      allBytes.addAll([
        (photo.width >> 8) & 0xFF,
        photo.width & 0xFF,
        0x00, // type byte — firmware isko 0 check karta hai
      ]);
      allBytes.addAll(columnMajor);
    }
    return allBytes;
  }

  /// Byte array ko C file text mein likho — Python script jaisa
  /// (15 bytes per line, LF line endings).
  static String formatDataH(List<int> bytes, int photoCount) {
    final lines = <String>[
      '#pragma once',
      '#include <Arduino.h>',
      '',
      '// Ignis RGB888 collection: $photoCount photos',
      '// $ledCount LEDs per vertical column',
      'const uint8_t PROGMEM pixels[${bytes.length}] = {',
    ];
    for (var i = 0; i < bytes.length; i += 15) {
      final chunk = bytes.sublist(i, i + 15 > bytes.length ? bytes.length : i + 15);
      final suffix = i + 15 < bytes.length ? ',' : '';
      lines.add(
        '  ${chunk.map((v) => '0x${v.toRadixString(16).toUpperCase().padLeft(2, '0')}').join(', ')}$suffix',
      );
    }
    lines.add('};');
    lines.add('');
    return lines.join('\n');
  }

  /// Rolandi ki .h file (File to C style array converter ki output)
  /// parse karo — Python ke parse_rgb888_header jaisa.
  ///
  /// `#define <NAME>_WIDTH` / `_HEIGHT` aur
  /// `static const (byte|uint8_t) <name>[] PROGMEM = {...}` parhta hai.
  /// Height yahin 50 par adjust ho jati hai (Python jaisa).
  static PhotoData parseHFile(String text, {String name = 'photo'}) {
    final clean = text
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    final widthMatch =
        RegExp(r'#\s*define\s+\w+_WIDTH\s+(\d+)').firstMatch(clean);
    final heightMatch =
        RegExp(r'#\s*define\s+\w+_HEIGHT\s+(\d+)').firstMatch(clean);
    if (widthMatch == null || heightMatch == null) {
      throw FormatException('Missing WIDTH or HEIGHT define.');
    }
    final width = int.parse(widthMatch.group(1)!);
    final height = int.parse(heightMatch.group(1)!);
    if (width < 1 || width > 65535 || height < 1) {
      throw FormatException('Invalid dimensions $width x $height.');
    }

    final arrayMatch = RegExp(
      r'static\s+const\s+(?:uint8_t|byte)\s+\w+\s*\[\s*\]\s*PROGMEM\s*=\s*\{(.*?)\}\s*;',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(clean);
    if (arrayMatch == null) {
      throw FormatException('RGB array not found (byte or uint8_t).');
    }

    final tokens = RegExp(r'0[xX][0-9a-fA-F]+|\b\d+\b')
        .allMatches(arrayMatch.group(1)!)
        .map((m) => m.group(0)!);
    final values = <int>[];
    for (final token in tokens) {
      final value = token.toLowerCase().startsWith('0x')
          ? int.parse(token.substring(2), radix: 16)
          : int.parse(token);
      if (value > 255) throw FormatException('Invalid byte $token.');
      values.add(value);
    }

    final expected = width * height * 3;
    if (values.length != expected) {
      throw FormatException(
        'Found ${values.length} bytes, expected $expected.',
      );
    }

    final adjusted = adjustHeight(values, width, height);
    return PhotoData(
      name: name,
      width: width,
      height: ledCount,
      rgb888: adjusted,
    );
  }

  /// Kisi data.h file ke text se byte array nikalo (test/verify ke liye).
  static List<int> parseDataHBytes(String text) {
    final arrayMatch = RegExp(
      r'const\s+uint8_t\s+PROGMEM\s+pixels\[\d+\]\s*=\s*\{(.*?)\}\s*;',
      dotAll: true,
    ).firstMatch(text);
    if (arrayMatch == null) {
      throw FormatException('pixels array not found in data.h.');
    }
    return RegExp(r'0[xX][0-9a-fA-F]+')
        .allMatches(arrayMatch.group(1)!)
        .map((m) => int.parse(m.group(0)!.substring(2), radix: 16))
        .toList();
  }

  /// data.h ki structure check karo: signature, count, har photo ki
  /// width + offset. Returns widths ki list (parse error par throw).
  /// Firmware ka indexImages() yahi karta hai.
  static List<int> parseDataHWidths(List<int> bytes) {
    if (bytes.length < 7) throw FormatException('data.h too short.');
    for (var i = 0; i < 6; i++) {
      if (bytes[i] != signature[i]) {
        throw FormatException('Wrong IGNIS signature.');
      }
    }
    final count = bytes[6];
    final widths = <int>[];
    var offset = 7;
    for (var i = 0; i < count; i++) {
      if (offset + 3 > bytes.length) {
        throw FormatException('Truncated photo header $i.');
      }
      final width = (bytes[offset] << 8) | bytes[offset + 1];
      final type = bytes[offset + 2];
      if (type != 0 || width == 0) {
        throw FormatException('Bad photo data at photo ${i + 1}.');
      }
      widths.add(width);
      offset += 3 + width * ledCount * 3;
    }
    if (offset != bytes.length) {
      throw FormatException(
        'Trailing bytes: offset $offset, length ${bytes.length}.',
      );
    }
    return widths;
  }
}
