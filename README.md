# صب الجاي — Spill the Tea

A **100% offline, peer-to-peer, Bluetooth-mesh messaging app** for Android & iOS,
built with Flutter. Inspired by the warm, glazed nightlight of the Ishtar Gate.

- **No servers, no internet, no SIM** — just Bluetooth Low Energy between phones.
- **Neighborhood thread** (`المواضيع → الجاي (الجوار)`) floods through the mesh.
- **Direct messages** (`الحضور → peer`) are end-to-end sealed between pairs.
- **QR pairing** exchanges public keys only; every BLE identity hello is Ed25519-signed.

## Brand & aesthetic

| Token | Value |
| --- | --- |
| App name (AR) | صب الجاي |
| Ground | `#0a1120` deep royal lapis |
| Surfaces | `#0f1a2e` / `#16243c` layered stone |
| Gold / Gold light | `#c9a44c` / `#e6d3a3` antique gold leaf |
| Brass / Turquoise / Pomegranate / Ivory | `#9a7b45` / `#3f9c93` / `#9d2b3f` / `#efe6d6` |
| Type | Reem Kufi (display) + Aref Ruqaa (accent), full RTL |

## Security model

- **Identity**: Ed25519 (signing) + X25519 (key agreement), generated at first
  launch. Private halves live only in `flutter_secure_storage`
  (Android Keystore / iOS Keychain).
- **Sessions**: derived deterministically from the two X25519 public keys via
  HKDF-SHA256 — nothing is persisted, nothing is stored per peer.
- **Wire**: every logical packet is framed, reassembled with hard size bounds,
  checked against a opcode whitelist, then AES-256-GCM opened. Badly formed or
  unsigned packets are dropped.
- **At rest**: Hive boxes store **ciphertext only**, resealed with a random
  per-install key that itself lives in secure storage.
- **Relay flood guard**: message IDs are honored once per 90 s window.

## Run it

```bash
flutter pub get
flutter run
```

> BLE does not work in emulators — use two physical phones.

### Required platform setup

`flutter create` generates the platform folders. Then add:

**Android** — `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
```

**iOS** — `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>صب الجاي يستخدم البلوتوث للتبادل المباشر بين الأجهزة.</string>
<key>NSCameraUsageDescription</key>
<string>نستخدم الكاميرا لمسح رمز الرفيق.</string>
<key>UIBackgroundModes</key>
<array><string>bluetooth-peripheral</string></array>
```

## Layout

```
lib/
  core/      crypto (TeaCrypto), sanitizer, QR payload, safe logging
  models/    Peer, StoredMessage
  storage/   secure identity store, encrypted Hive vault, backup service
  mesh/      BLE service, framing, message envelopes, protocol hello
  services/  bootstrap, messaging (threads/previews)
  screens/   onboarding, radar, chats, chat, QR my-card & scan, settings
  widgets/   tea logo, orbit painter, avatars, gold rules
```

## Honest v1 limits

- Broadcast messages are re-sealed per neighbor-hop (still end-to-end readable
  only by pairwise-paired members). See `MeshService.relayBroadcast`.
- Bam-flood relays are capped at 3 hops; direct DMs are 1 hop in v1.