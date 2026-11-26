/// Photo transforms — export se pehle lagte hain.
///
/// Ye converter ka hissa nahi: converter hamesha row-major bytes ko
/// jaisa hai waisa leta hai. Ye transforms user ki editing (flip /
/// brightness / rotate) ko export bytes par lagate hain.
library;

import 'package:r_art_led_performance/ignis/ignis_converter.dart';

class PhotoTransforms {
  /// Rows ko ulta karo (top <-> bottom).
  ///
  /// Rolandi ke online converter (FileToCArray) ki BMP row order
  /// unconfirmed hai — agar hardware test par photo ulti dikhe to
  /// ye toggle theek karega.
  static List<int> flipVertical(List<int> rowMajor, int width, int height) {
    final out = <int>[];
    for (var y = height - 1; y >= 0; y--) {
      final start = y * width * 3;
      out.addAll(rowMajor.sublist(start, start + width * 3));
    }
    return out;
  }

  /// 90 degree clockwise ghumao.
  static PhotoData rotate90(PhotoData photo) {
    final w = photo.width;
    final h = photo.height;
    final out = List<int>.filled(w * h * 3, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Nayi position: (h - 1 - y, x).
        final nx = h - 1 - y;
        final ny = x;
        final src = (y * w + x) * 3;
        final dst = (ny * h + nx) * 3;
        out[dst] = photo.rgb888[src];
        out[dst + 1] = photo.rgb888[src + 1];
        out[dst + 2] = photo.rgb888[src + 2];
      }
    }
    return PhotoData(name: photo.name, width: h, height: w, rgb888: out);
  }

  /// Brightness scale karo (factor 1.0 = jaisa hai). 0..255 clamp.
  static List<int> brightness(List<int> rgb, double factor) {
    if (factor == 1.0) return List<int>.from(rgb);
    return rgb
        .map((v) => (v * factor).round().clamp(0, 255))
        .toList();
  }
}
