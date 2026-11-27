// ============================================================
// R Art LED Performance — USB receiver firmware (ESP8266 NodeMCU)
//
// Phase 2 firmware for Rolandi Pisadze's LED staff.
//
// WHAT IT DOES
//   The R Art app (web demo) sends the finished show straight to
//   this board over USB — no manual data.h export / re-flash:
//     1. App: "Send to Device (USB)" (Chrome / Edge, Web Serial).
//     2. This sketch receives one "RART" frame over Serial
//        (115200 baud), saves it to LittleFS as /data.bin and
//        replies "OK".
//     3. The show plays from /data.bin with the same timing and
//        buttons as the original sketch (sketch_nov23a.ino):
//        2000 us per column, 3000 ms per photo, 3 sections x 10,
//        UP/DOWN select section, short START plays the section,
//        long START (1200 ms) plays all 30.
//
// FRAME FORMAT (see lib/services/usb_protocol.dart in the app)
//   "RART" (4 bytes) + LED count uint16 big-endian
//   + payload length uint32 little-endian
//   + payload (Ignis data.h bytes, binary — NOT the C text)
//   + CRC16-CCITT (poly 0x1021, init 0xFFFF), 2 bytes big-endian
//
// DATA FORMAT (Ignis, same as the original data.h)
//   "IGNIS\0" + photo count (30) + per photo: width uint16 BE,
//   type byte (0 = RGB, 3 bytes/px; 1 = RGBW, 4 bytes/px),
//   column-major pixels. LED 0 = row 0 (image top).
//
// SETUP (Arduino IDE)
//   Board: NodeMCU 1.0 (ESP-12E) — same as the original sketch.
//   Libraries: Adafruit NeoPixel, LittleFS (built into ESP8266 core).
//   Flash this sketch once. After that, shows arrive over USB from
//   the app — no re-flash needed to change photos.
//   LED_COUNT below MUST match the app's LED setting (default 50,
//   up to 512). If the app sends a different count, the board
//   replies "ERR LED COUNT" and keeps the old show.
//   RGBW strips (SK6812 RGBW): set LED_RGBW to true below.
//
// PINS (same as the original sketch)
//   LED data: D0. Buttons: UP D6, START D5, DOWN D4.
//   NOTE: the original sketch's Serial prints swap the UP/DOWN
//   labels — this sketch prints the correct pin names.
// ============================================================

#include <Adafruit_NeoPixel.h>
#include <LittleFS.h>

// =====================================
// PINS
// =====================================

#define LED_PIN D0
#define LED_COUNT 50

#define BTN_UP D6
#define BTN_START D5
#define BTN_DOWN D4

// =====================================
// SETTINGS
// =====================================

#define BRIGHTNESS 50
#define PHOTO_TIME 3000
#define LONG_PRESS 1200
#define DEBOUNCE 35
#define COLUMN_INTERVAL_US 2000

#define PHOTO_COUNT 30

// true = SK6812 RGBW strip (4 bytes per pixel, type 0x01).
// false = normal RGB strip (3 bytes per pixel, type 0x00).
#define LED_RGBW false

// =====================================
// LED STRIP
// =====================================

#if LED_RGBW
Adafruit_NeoPixel leds(LED_COUNT, LED_PIN, NEO_GRBW + NEO_KHZ800);
#else
Adafruit_NeoPixel leds(LED_COUNT, LED_PIN, NEO_GRB + NEO_KHZ800);
#endif

// =====================================
// IGNIS SIGNATURE
// =====================================

const uint8_t SIGNATURE[6] = {0x49, 0x47, 0x4E, 0x49, 0x53, 0x00};

// =====================================
// IMAGE DATA (read from LittleFS file)
// =====================================

uint16_t imageWidth[PHOTO_COUNT];
uint32_t imageOffset[PHOTO_COUNT];
uint8_t imageType[PHOTO_COUNT];

uint8_t totalPhotos = 0;
bool hasShow = false;

// One column of pixels (max 512 LEDs x 4 bytes for RGBW).
uint8_t colBuf[512 * 4];

// =====================================
// PLAYBACK
// =====================================

uint8_t selectedSection = 0;
uint8_t currentPhoto = 0;
uint16_t currentColumn = 0;

bool playing = false;
bool playAll = false;

unsigned long photoStartTime = 0;
unsigned long lastColumnTime = 0;

// =====================================
// BUTTON STRUCTURE
// =====================================

struct Button {
  uint8_t pin;
  bool stable;
  bool lastRaw;
  unsigned long changedAt;
  bool pressedEvent;
  bool releasedEvent;
};

Button upButton = {BTN_UP, HIGH, HIGH, 0, false, false};
Button downButton = {BTN_DOWN, HIGH, HIGH, 0, false, false};
Button startButton = {BTN_START, HIGH, HIGH, 0, false, false};

unsigned long startTime = 0;
bool startHeld = false;
bool longStarted = false;

// =====================================
// CRC16-CCITT (poly 0x1021, init 0xFFFF)
// =====================================

uint16_t crc16Update(uint16_t crc, uint8_t b) {
  crc ^= (uint16_t)b << 8;
  for (uint8_t i = 0; i < 8; i++) {
    crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) : (crc << 1);
  }
  return crc;
}

// =====================================
// BUTTON UPDATE
// =====================================

void updateButton(Button &b, const char *name) {
  b.pressedEvent = false;
  b.releasedEvent = false;
  bool raw = digitalRead(b.pin);
  if (raw != b.lastRaw) {
    b.lastRaw = raw;
    b.changedAt = millis();
  }
  if (millis() - b.changedAt >= DEBOUNCE) {
    if (raw != b.stable) {
      b.stable = raw;
      if (raw == LOW) {
        b.pressedEvent = true;
        Serial.print("[BUTTON] ");
        Serial.print(name);
        Serial.println(" PRESSED");
      } else {
        b.releasedEvent = true;
        Serial.print("[BUTTON] ");
        Serial.print(name);
        Serial.println(" RELEASED");
      }
    }
  }
}

// =====================================
// INDEX IMAGES (from /data.bin)
// =====================================

bool indexImages() {
  File f = LittleFS.open("/data.bin", "r");
  if (!f) {
    Serial.println("[DATA] No /data.bin yet.");
    return false;
  }

  uint8_t header[7];
  if (f.read(header, 7) != 7) {
    Serial.println("[ERROR] Short header.");
    f.close();
    return false;
  }
  for (uint8_t i = 0; i < 6; i++) {
    if (header[i] != SIGNATURE[i]) {
      Serial.println("[ERROR] WRONG SIGNATURE");
      f.close();
      return false;
    }
  }
  totalPhotos = header[6];
  Serial.print("[DATA] PHOTOS: ");
  Serial.println(totalPhotos);
  if (totalPhotos != PHOTO_COUNT) {
    Serial.println("[ERROR] PHOTO COUNT ERROR");
    f.close();
    return false;
  }

  uint32_t offset = 7;
  for (uint8_t i = 0; i < PHOTO_COUNT; i++) {
    uint8_t photoHeader[3];
    f.seek(offset, SeekSet);
    if (f.read(photoHeader, 3) != 3) {
      Serial.println("[ERROR] Truncated photo header.");
      f.close();
      return false;
    }
    uint16_t width = ((uint16_t)photoHeader[0] << 8) | photoHeader[1];
    uint8_t type = photoHeader[2];
    if ((type != 0 && type != 1) || width == 0) {
      Serial.print("[ERROR] PHOTO DATA: ");
      Serial.println(i + 1);
      f.close();
      return false;
    }
    if (type == 1 && !LED_RGBW) {
      Serial.println("[ERROR] RGBW show on RGB strip — set LED_RGBW true.");
      f.close();
      return false;
    }
    imageWidth[i] = width;
    imageType[i] = type;
    imageOffset[i] = offset + 3;
    offset += 3 + (uint32_t)width * LED_COUNT * (type == 1 ? 4 : 3);
  }
  f.close();
  Serial.println("[DATA] ALL 30 PHOTOS LOADED");
  return true;
}

// =====================================
// CLEAR LEDS
// =====================================

void clearLeds() {
  leds.clear();
  leds.show();
}

// =====================================
// SECTION INDICATORS
// =====================================

void showIndicators() {
  leds.clear();
  leds.setPixelColor(
    LED_COUNT - 3 + selectedSection,
    leds.Color(255, 255, 255)
  );
  leds.show();
  Serial.print("[SECTION] SELECTED: ");
  Serial.println(selectedSection + 1);
}

// =====================================
// DISPLAY PHOTO COLUMN (from file)
// =====================================

void displayColumn(uint8_t photo, uint16_t column) {
  File f = LittleFS.open("/data.bin", "r");
  if (!f) return;
  const uint8_t bpp = imageType[photo] == 1 ? 4 : 3;
  const uint32_t lineLength = (uint32_t)LED_COUNT * bpp;
  f.seek(imageOffset[photo] + (uint32_t)column * lineLength, SeekSet);
  if (f.read(colBuf, lineLength) != (int)lineLength) {
    f.close();
    return;
  }
  f.close();
  for (int i = 0; i < LED_COUNT; i++) {
    const uint8_t *p = colBuf + i * bpp;
    if (bpp == 4) {
      leds.setPixelColor(i, leds.Color(p[0], p[1], p[2], p[3]));
    } else {
      leds.setPixelColor(i, leds.Color(p[0], p[1], p[2]));
    }
  }
  leds.show();
}

// =====================================
// SECTION UP / DOWN
// =====================================

void sectionUp() {
  selectedSection = (selectedSection + 1) % 3;
  showIndicators();
}

void sectionDown() {
  selectedSection = (selectedSection + 2) % 3;
  showIndicators();
}

// =====================================
// START SELECTED SECTION / ALL PHOTOS
// =====================================

void startSelectedSection() {
  playing = true;
  playAll = false;
  currentPhoto = selectedSection * 10;
  currentColumn = 0;
  photoStartTime = millis();
  lastColumnTime = micros();
  clearLeds();
  Serial.print("[PLAY] SECTION ");
  Serial.println(selectedSection + 1);
}

void startAllPhotos() {
  playing = true;
  playAll = true;
  currentPhoto = 0;
  currentColumn = 0;
  photoStartTime = millis();
  lastColumnTime = micros();
  clearLeds();
  Serial.println("[PLAY] ALL PHOTOS");
}

void nextPhoto() {
  currentPhoto++;
  currentColumn = 0;
  photoStartTime = millis();
  if (playAll) {
    if (currentPhoto >= PHOTO_COUNT) {
      playing = false;
      clearLeds();
      Serial.println("[PLAY] FINISHED");
      showIndicators();
      return;
    }
  } else {
    const uint8_t last = selectedSection * 10 + 10;
    if (currentPhoto >= last) {
      currentPhoto = selectedSection * 10;
    }
  }
  Serial.print("[PLAY] PHOTO ");
  Serial.println(currentPhoto + 1);
}

// =====================================
// RECEIVE "RART" FRAME OVER SERIAL
// =====================================

bool readExact(uint8_t *buf, uint32_t len, uint16_t timeoutMs) {
  Serial.setTimeout(timeoutMs);
  return Serial.readBytes((char *)buf, len) == len;
}

void receiveFrame() {
  // "RART" already consumed by the caller.
  Serial.println("[USB] Receiving show…");
  playing = false;
  clearLeds();

  uint8_t header[6];
  if (!readExact(header, 6, 5000)) {
    Serial.println("ERR TIMEOUT");
    return;
  }
  const uint16_t frameLeds = ((uint16_t)header[0] << 8) | header[1];
  const uint32_t length = (uint32_t)header[2] |
      ((uint32_t)header[3] << 8) |
      ((uint32_t)header[4] << 16) |
      ((uint32_t)header[5] << 24);

  if (frameLeds != LED_COUNT) {
    Serial.println("ERR LED COUNT");
    Serial.print("[USB] App sent ");
    Serial.print(frameLeds);
    Serial.print(" LEDs, firmware is ");
    Serial.println(LED_COUNT);
    return;
  }
  if (length == 0 || length > 8UL * 1024 * 1024) {
    Serial.println("ERR LENGTH");
    return;
  }

  File f = LittleFS.open("/data.bin.tmp", "w");
  if (!f) {
    Serial.println("ERR FILE");
    return;
  }

  // CRC covers magic + ledCount + length + payload.
  uint16_t crc = 0xFFFF;
  for (uint8_t i = 0; i < 4; i++) crc = crc16Update(crc, "RART"[i]);
  crc = crc16Update(crc, header[0]);
  crc = crc16Update(crc, header[1]);
  for (uint8_t i = 0; i < 4; i++) crc = crc16Update(crc, header[2 + i]);

  uint32_t remaining = length;
  uint8_t chunk[256];
  bool ok = true;
  while (remaining > 0) {
    const uint32_t want = remaining > sizeof(chunk) ? sizeof(chunk) : remaining;
    if (!readExact(chunk, want, 5000)) {
      ok = false;
      break;
    }
    for (uint32_t i = 0; i < want; i++) crc = crc16Update(crc, chunk[i]);
    if (f.write(chunk, want) != want) {
      ok = false;
      break;
    }
    remaining -= want;
    // Small chase pattern while receiving.
    leds.setPixelColor((length - remaining) % LED_COUNT, leds.Color(0, 80, 255));
    leds.show();
  }
  f.close();

  if (!ok) {
    Serial.println("ERR TIMEOUT");
    LittleFS.remove("/data.bin.tmp");
    return;
  }

  uint8_t crcBytes[2];
  if (!readExact(crcBytes, 2, 5000)) {
    Serial.println("ERR TIMEOUT");
    LittleFS.remove("/data.bin.tmp");
    return;
  }
  const uint16_t sentCrc = ((uint16_t)crcBytes[0] << 8) | crcBytes[1];
  if (sentCrc != crc) {
    Serial.println("ERR CRC");
    LittleFS.remove("/data.bin.tmp");
    return;
  }

  LittleFS.remove("/data.bin");
  LittleFS.rename("/data.bin.tmp", "/data.bin");
  clearLeds();
  if (indexImages()) {
    hasShow = true;
    Serial.println("OK");
    Serial.print("[USB] Saved ");
    Serial.print(length);
    Serial.println(" bytes.");
    showIndicators();
  } else {
    Serial.println("ERR DATA");
    hasShow = false;
  }
}

// =====================================
// SETUP
// =====================================

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println();
  Serial.println("[SYSTEM] R Art USB receiver");
  Serial.print("[SYSTEM] LEDs: ");
  Serial.println(LED_COUNT);
#if LED_RGBW
  Serial.println("[SYSTEM] Strip: RGBW");
#else
  Serial.println("[SYSTEM] Strip: RGB");
#endif

  pinMode(BTN_UP, INPUT_PULLUP);
  pinMode(BTN_START, INPUT_PULLUP);
  pinMode(BTN_DOWN, INPUT_PULLUP);

  leds.begin();
  leds.setBrightness(BRIGHTNESS);
  clearLeds();

  if (!LittleFS.begin()) {
    Serial.println("[FATAL] LittleFS mount failed.");
    while (true) delay(100);
  }

  hasShow = indexImages();
  if (!hasShow) {
    Serial.println("[WAIT] No show yet — send one from the R Art app (USB).");
  }
  showIndicators();
  Serial.println("[SYSTEM] READY");
}

// =====================================
// MAIN LOOP
// =====================================

void loop() {
  // A new show arriving over USB? Peek for the "RART" magic.
  if (Serial.available() >= 4) {
    uint8_t magic[4];
    Serial.peekBytes((char *)magic, 4);
    if (magic[0] == 'R' && magic[1] == 'A' && magic[2] == 'R' &&
        magic[3] == 'T') {
      Serial.readBytes((char *)magic, 4);
      receiveFrame();
      return;
    }
    // Not a frame — drop one byte so junk cannot stall the loop.
    Serial.read();
  }

  // Waiting pattern when no show is stored yet.
  if (!hasShow) {
    const uint8_t pos = (millis() / 120) % LED_COUNT;
    leds.clear();
    leds.setPixelColor(pos, leds.Color(0, 40, 120));
    leds.show();
    delay(20);
    return;
  }

  // READ BUTTONS
  updateButton(upButton, "UP");
  updateButton(downButton, "DOWN");
  updateButton(startButton, "START");

  if (upButton.pressedEvent) sectionUp();
  if (downButton.pressedEvent) sectionDown();

  if (startButton.pressedEvent) {
    startHeld = true;
    longStarted = false;
    startTime = millis();
  }
  if (startHeld && startButton.stable == LOW && !longStarted) {
    if (millis() - startTime >= LONG_PRESS) {
      startAllPhotos();
      longStarted = true;
    }
  }
  if (startButton.releasedEvent && startHeld) {
    if (!longStarted) startSelectedSection();
    startHeld = false;
  }

  // PHOTO PLAYBACK
  if (playing) {
    if (micros() - lastColumnTime >= COLUMN_INTERVAL_US) {
      lastColumnTime = micros();
      displayColumn(currentPhoto, currentColumn);
      currentColumn++;
      if (currentColumn >= imageWidth[currentPhoto]) currentColumn = 0;
    }
    if (millis() - photoStartTime >= PHOTO_TIME) nextPhoto();
  }
}
