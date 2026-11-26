# R Art LED Performance — Demo App (Phase 1)

Flutter app for Rolandi Pisadze's POV LED staff. Photo import karo, timeline
banao, POV preview dekho, aur **data.h export karo** — jo firmware
(`sketch_nov23a.ino`) mein flash hoti hai.

## Run karo

```bash
export PATH=~/workspace/flutter-sdk/bin:$PATH
flutter run            # phone / emulator
flutter run -d chrome  # web preview
flutter build web      # release web build
flutter test           # saare tests
```

## Ignis format (Rolandi ka algorithm — exact)

Ye app Rolandi ke apne Python script `batch_rgb888_to_ignis.py` ka Dart
port hai. Format mein koi change nahi — hamari data.h uski data.h se
byte-for-byte milti hai (test dekho: `test/ignis_converter_test.dart`).

1. **Input:** photo ke RGB888 bytes, row-major (width x height x 3).
2. **Height adjust → 50 LEDs:** chhoti ho to kaale rows centered add karo
   (top = missing ~/ 2); bari ho to beech ki 50 rows crop karo.
3. **Row-major → column-major:** har column x ke liye, rows y = 0..49.
4. **data.h bytes:** `"IGNIS"` signature (`49 47 4E 49 53 00`) + photo count
   (1 byte) + har photo: width 2 bytes big-endian + `0x00` type byte +
   column-major RGB bytes. C array, 15 bytes per line.

Firmware ke mutabiq (sketch_nov23a.ino):

- LED 0 = row 0 (image ki pehli row).
- Har column 2000us, har photo 3000ms.
- **Firmware ko EXACTLY 30 photos chahiye** (PHOTO_COUNT 30) — is liye
  export hamesha 30 entries likhta hai; khaali slot 1-column kaale photo
  ke tor par export hota hai.
- Sections: 1 = photos 1–10, 2 = 11–20, 3 = 21–30.

## Features (Phase 1)

- Photo import: JPG / PNG / BMP / WebP (`image` package se decode).
- Timeline: 3 sections x 10 photos, section ke andar drag-reorder,
  per-photo duration (default 3s).
- Editor: vertical flip (BMP row-order correction), brightness,
  rotate 90°, duration, replace / remove.
- POV preview: LED column ka left-to-right sweep + persistence trail
  (simulation — asal display hardware par hota hai).
- Export data.h: validation + save (web par download hota hai).
- Project save/open: JSON (photos base64 ke sath).
- Branding: "R Art" text logo (asal logo abhi nahi aaya).

## Abhi baaqi hai (hardware test — Rolandi ki taraf)

- **Orientation:** agar staff par photo ulti dikhe to editor mein
  Vertical flip on karo aur dobara export karo. BMP row order
  unconfirmed hai — ye toggle isi liye hai.
- **Asal display:** video se verify nahi ho sakta (camera POV nahi
  pakarta) — Rolandi ko apni staff par aankhon se dekhna hai.
- USB transfer, BLE/Wi-Fi, music sync, effects — Phase 2+ (firmware
  mein abhi USB-receive mode hai hi nahi; manual flash only).

## Structure

```
lib/
  ignis/
    ignis_converter.dart  # converter (pure Dart) + .h / data.h parsers
    photo_transforms.dart # flip / rotate / brightness
    image_decode.dart     # JPG/PNG/BMP/WebP -> RGB888
  models/
    project.dart          # 30 slots, 3 sections, export (30 photos)
  ui/
    pov_preview.dart      # POV sweep animation
    photo_editor.dart     # editor bottom sheet
  main.dart               # home (timeline) + preview screen
test/
  fixtures/               # Rolandi ki ground-truth files
    1.h.txt               # skull photo (61x50)
    data_1photo.h.txt     # uski data.h (9160 bytes)
    data_30photos.h.txt   # uski 30-photo data.h (245347 bytes)
  ignis_converter_test.dart  # byte-for-byte test + padding/crop tests
  project_test.dart          # export-30 + transform tests
  widget_test.dart           # home screen smoke test
```
