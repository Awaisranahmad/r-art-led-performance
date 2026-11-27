// R Art LED Performance — Web Serial shim.
//
// ESP32 dev boards connect over USB as a serial port (CP2102 / CH340
// USB-serial chip). The browser API for that is Web Serial
// (navigator.serial) — NOT WebUSB: the operating system's driver owns
// the USB-serial interface, so WebUSB cannot claim it. Web Serial
// works in Chrome / Edge on desktop; Firefox / Safari do not support
// it (the app then offers the manual data.h download instead).
//
// The Dart side (lib/services/usb_service.dart) calls these functions
// through dart:js_interop. All functions return Promises.
//
// Protocol (see lib/services/usb_protocol.dart): the app sends one
// "RART" frame — magic + LED count + length + Ignis payload + CRC16.
// The receiver firmware (firmware/r_art_usb_receiver.ino) saves it to
// LittleFS and replies "OK\n" (or "ERR ...\n" on failure).

window.rartSerial = (() => {
  let port = null;
  let writer = null;
  let reader = null;

  function isSupported() {
    return typeof navigator !== 'undefined' && 'serial' in navigator;
  }

  async function connect() {
    if (!isSupported()) throw new Error('Web Serial not supported');
    // Opens the browser's port chooser — the user picks the ESP32.
    port = await navigator.serial.requestPort();
    await port.open({ baudRate: 115200 });
    writer = port.writable.getWriter();
    reader = port.readable.getReader();
    return 'OK';
  }

  async function writeBase64(b64) {
    if (!writer) throw new Error('Not connected');
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    let written = 0;
    // Small chunks + short pauses: cheap USB-serial chips drop data
    // when flooded at full speed.
    const CHUNK = 1024;
    for (let i = 0; i < bytes.length; i += CHUNK) {
      const chunk = bytes.slice(i, i + CHUNK);
      await writer.write(chunk);
      written += chunk.length;
      await new Promise((r) => setTimeout(r, 10));
    }
    return written;
  }

  async function readAck(timeoutMs) {
    if (!reader) throw new Error('Not connected');
    let buf = '';
    const deadline = Date.now() + timeoutMs;
    const decoder = new TextDecoder();
    while (Date.now() < deadline) {
      const remaining = deadline - Date.now();
      const result = await Promise.race([
        reader.read(),
        new Promise((r) =>
          setTimeout(() => r({ timeout: true }), remaining),
        ),
      ]);
      if (result && result.timeout) break;
      if (!result || result.done) break;
      if (result.value) {
        buf += decoder.decode(result.value, { stream: true });
        if (buf.includes('OK')) return 'OK';
        if (buf.includes('ERR')) throw new Error(buf.trim());
        // Keep the last line only — the firmware also prints logs.
        const lines = buf.split('\n');
        buf = lines[lines.length - 1];
      }
    }
    throw new Error('TIMEOUT');
  }

  async function disconnect() {
    try {
      if (reader) {
        await reader.cancel();
        reader.releaseLock();
      }
    } catch (e) {
      /* already closed */
    }
    try {
      if (writer) {
        await writer.close();
        writer.releaseLock();
      }
    } catch (e) {
      /* already closed */
    }
    try {
      if (port) await port.close();
    } catch (e) {
      /* already closed */
    }
    port = null;
    writer = null;
    reader = null;
  }

  return { isSupported, connect, writeBase64, readAck, disconnect };
})();
