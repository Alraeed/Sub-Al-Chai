/// Bluetooth Low Energy constants for صب الجاي.
/// These are public protocol constants, not secrets.
abstract final class BleConstants {
  /// App mesh service UUID (128-bit, custom).
  static const String serviceUuid = 'a3c9a1b2-0d4e-4f6a-9f12-0c1d2e3f4a5b';

  /// Identity characteristic — read-only, holds the signed hello.
  static const String identityCharUuid = 'a3c9a1b2-0d4e-4f6a-9f12-0c1d2e3f4a5c';

  /// Write characteristic — centrals write framed data here.
  static const String writeCharUuid = 'a3c9a1b2-0d4e-4f6a-9f12-0c1d2e3f4a5d';

  /// Notify characteristic — peripheral pushes framed data here.
  static const String notifyCharUuid = 'a3c9a1b2-0d4e-4f6a-9f12-0c1d2e3f4a5e';

  /// WiFi-direct-style magic for frame headers ('ST').
  static const int magicByte0 = 0x53;
  static const int magicByte1 = 0x54;

  /// Preferred ATT MTU; the smallest practical cap we honor.
  static const int preferredMtu = 185;

  /// Data frame opcodes inside a GATT write/notification.
  static const int frameOpData = 0x21;

  /// Bounded queue sizes.
  static const int maxAssemblerEntries = 24;
  static const Duration assemblerTtl = Duration(seconds: 30);
}
