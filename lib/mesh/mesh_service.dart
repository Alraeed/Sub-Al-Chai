import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/foundation.dart';

import '../core/crypto/dm_ratchet.dart';
import '../core/crypto/tea_crypto.dart';
import '../core/utils/safe_log.dart';
import '../core/utils/sanitizer.dart';
import '../l10n/app_strings.dart';
import '../models/peer.dart';
import '../models/stored_message.dart';
import '../storage/local_vault.dart';
import '../storage/secure_identity_store.dart';
import 'ble_constants.dart';
import 'fragmenter.dart';
import 'message_envelope.dart';
import 'protocol.dart';
import 'session_store.dart';

/// Mesh coordinator — BLE peripheral + central in one object.
///
/// Every node advertises the same service; links are classic GATT pairs.
/// Logical packets are framed, re-assembled with hard bounds, verified, and
/// only then handed to the messaging layer. Message plaintext is never
/// written to logs.
class MeshService extends ChangeNotifier {
  MeshService._() {
    if (kIsWeb) {
      return;
    }
    _central = CentralManager();
    _peripheral = PeripheralManager();
    _central.discovered.listen(_onDiscovered).onError((Object e) {
      SafeLog.error('mesh', 'discovered listener error', e);
    });
    _central.connectionStateChanged
        .listen(_onCentralConnectionState)
        .onError((Object e) {
      SafeLog.error('mesh', 'central connection listener error', e);
    });
    _central.characteristicNotified
        .listen(_onCharacteristicNotified)
        .onError((Object e) {
      SafeLog.error('mesh', 'notified listener error', e);
    });
    _peripheral.characteristicWriteRequested
        .listen(_onWriteRequested)
        .onError((Object e) {
      SafeLog.error('mesh', 'write listener error', e);
    });
    _peripheral.characteristicReadRequested
        .listen(_onReadRequested)
        .onError((Object e) {
      SafeLog.error('mesh', 'read listener error', e);
    });
    _peripheral.connectionStateChanged
        .listen(_onPeripheralConnectionState)
        .onError((Object e) {
      SafeLog.error('mesh', 'peripheral connection listener error', e);
    });
  }

  static MeshService? _instance;

  static MeshService getInstance() {
    return _instance ??= MeshService._();
  }

  late final CentralManager _central;
  late final PeripheralManager _peripheral;

  final FrameAssembler _centralFrames = FrameAssembler();
  final FrameAssembler _peripheralFrames = FrameAssembler();

  final Map<String, _CentralLink> _centralLinks = <String, _CentralLink>{};
  final Map<String, _PeripheralLink> _peripheralLinks =
      <String, _PeripheralLink>{};

  /// shortId (hex 8) -> peerId.
  final Map<String, String> _peerIdByShortId = <String, String>{};

  final Map<String, Peer> _onlinePeers = <String, Peer>{};
  final StreamController<MeshUiEvent> _events = StreamController.broadcast();

  IdentityMaterial? _identity;
  Uint8List _helloCache = Uint8List(0);
  Uint8List _preKeyAnnounceCache = Uint8List(0);
  GATTCharacteristic? _localNotifyChar;
  GATTService? _service;
  bool _serviceAdded = false;
  String _myShortId = '';
  String? lastError;
  bool _tornDown = false;
  bool _scanning = false;
  bool _advertising = false;
  bool _relayEnabled = true;

  /// Broadcast thread token for neighborhood chat.
  static const String neighborhoodThread = '__neighborhood__';

  Stream<MeshUiEvent> get events => _events.stream;
  bool get isScanning => _scanning;
  bool get isAdvertising => _advertising;
  bool get relayEnabled => _relayEnabled;

  void setRelayEnabled(bool enabled) {
    if (_relayEnabled == enabled) {
      return;
    }
    _relayEnabled = enabled;
    notifyListeners();
  }

  String get myShortId => _myShortId;

  List<Peer> get onlinePeers {
    final List<Peer> peers = _onlinePeers.values.toList(growable: false);
    peers.sort((Peer a, Peer b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return peers;
  }

  int get onlineCount => _onlinePeers.length;

  bool get bleOn =>
      !kIsWeb && _central.state == BluetoothLowEnergyState.poweredOn;

  Future<void> start({required IdentityMaterial identity}) async {
    if (_tornDown || _identity != null) {
      return;
    }
    _identity = identity;
    lastError = null;
    final Uint8List combined = Uint8List(64);
    combined.setAll(0, identity.signPublic);
    combined.setAll(32, identity.dhPublic);
    _myShortId = shortToHex(combined);
    _helloCache = await buildHello(
      signKeyPair: identity.signKeyPair,
      signPublicKey: identity.signPublic,
      dhPublicKey: identity.dhPublic,
      displayName: identity.displayName,
    );

    if (!kIsWeb) {
      try {
        await DmSessionStore.open();
        _preKeyAnnounceCache = await _buildPreKeyAnnounce();
      } on Object catch (e) {
        SafeLog.error('mesh', 'dm session init failed; v1 DMs only', e);
      }
    }

    if (kIsWeb) {
      notifyListeners();
      return;
    }

    final bool centralOk = await _central.authorize();
    final bool peripheralOk = await _peripheral.authorize();
    if (!centralOk || !peripheralOk) {
      SafeLog.error('mesh', 'authorization refused');
      lastError = AppStrings.errorPermissionDenied;
      notifyListeners();
      return;
    }

    final GATTService service = _service ??= _buildService();
    // The service is registered once per process: after a shutdown the same
    // object must be reused, otherwise _localNotifyChar would point at a
    // characteristic the platform never registered.
    if (!_serviceAdded) {
      await _peripheral.addService(service);
      _serviceAdded = true;
    }
    try {
      await _peripheral.startAdvertising(
        Advertisement(
          name: AppStrings.appName,
          serviceUUIDs: <UUID>[UUID.fromString(BleConstants.serviceUuid)],
        ),
      );
      _advertising = true;
    } on Object catch (e) {
      SafeLog.error('mesh', 'startAdvertising failed', e);
      lastError = AppStrings.errorGeneric;
    }
    await _startScan();
    notifyListeners();
  }

  Future<void> _startScan() async {
    try {
      await _central.startDiscovery(
        serviceUUIDs: <UUID>[UUID.fromString(BleConstants.serviceUuid)],
      );
      _scanning = true;
    } on Object catch (e) {
      SafeLog.error('mesh', 'startDiscovery failed', e);
      lastError = AppStrings.errorGeneric;
    }
  }

  GATTService _buildService() {
    final GATTCharacteristic identityChar = GATTCharacteristic.mutable(
      uuid: UUID.fromString(BleConstants.identityCharUuid),
      properties: const <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.read,
      ],
      permissions: const <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.read,
      ],
      descriptors: const <GATTDescriptor>[],
    );
    final GATTCharacteristic writeChar = GATTCharacteristic.mutable(
      uuid: UUID.fromString(BleConstants.writeCharUuid),
      properties: const <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
      ],
      permissions: const <GATTCharacteristicPermission>[
        GATTCharacteristicPermission.write,
      ],
      descriptors: const <GATTDescriptor>[],
    );
    final GATTCharacteristic notifyChar = GATTCharacteristic.mutable(
      uuid: UUID.fromString(BleConstants.notifyCharUuid),
      properties: const <GATTCharacteristicProperty>[
        GATTCharacteristicProperty.notify,
      ],
      permissions: const <GATTCharacteristicPermission>[],
      descriptors: const <GATTDescriptor>[],
    );
    _localNotifyChar = notifyChar;
    return GATTService(
      uuid: UUID.fromString(BleConstants.serviceUuid),
      isPrimary: true,
      includedServices: const <GATTService>[],
      characteristics: <GATTCharacteristic>[
        identityChar,
        writeChar,
        notifyChar,
      ],
    );
  }
// ------------------------------------------------------------- central role

  void _onDiscovered(DiscoveredEventArgs args) {
    final String key = args.peripheral.uuid.toString();
    if (_centralLinks.containsKey(key)) {
      return;
    }
    unawaited(_establishCentralLink(args.peripheral));
  }

  Future<void> _establishCentralLink(Peripheral peripheral) async {
    final String key = peripheral.uuid.toString();
    final _CentralLink link = _CentralLink(peripheral);
    _centralLinks[key] = link;
    try {
      await _central.connect(peripheral);
      int mtu = BleConstants.preferredMtu;
      try {
        mtu = await _central.requestMTU(
          peripheral,
          mtu: BleConstants.preferredMtu,
        );
      } on Object catch (e) {
        SafeLog.error('mesh', 'requestMTU failed; using default', e);
      }
      link.writeMtu = mtu;
      final List<GATTService> services =
          await _central.discoverGATT(peripheral);
      final GATTService? mesh = _findService(services);
      if (mesh == null) {
        SafeLog.info('mesh', 'peer without our service; dropping link');
        await _central.disconnect(peripheral);
        _centralLinks.remove(key);
        return;
      }
      final GATTCharacteristic? writeChar = _findChar(
        mesh,
        BleConstants.writeCharUuid,
      );
      final GATTCharacteristic? notifyChar = _findChar(
        mesh,
        BleConstants.notifyCharUuid,
      );
      final GATTCharacteristic? identityChar = _findChar(
        mesh,
        BleConstants.identityCharUuid,
      );
      if (writeChar == null || notifyChar == null || identityChar == null) {
        await _central.disconnect(peripheral);
        _centralLinks.remove(key);
        return;
      }
      link.writeChar = writeChar;
      link.notifyChar = notifyChar;

      final int? writeLength = await _safeMaxWriteLength(peripheral);
      link.fragmenter = Fragmenter(
        (writeLength == null || writeLength < 20)
            ? 158
            : writeLength - Fragmenter.frameHeaderLength,
      );

      await _central.setCharacteristicNotifyState(
        peripheral,
        notifyChar,
        state: true,
      );
      final Uint8List remoteHello = await _central.readCharacteristic(
        peripheral,
        identityChar,
      );
      final HelloIdentity? hello = await parseHello(remoteHello);
      if (hello != null) {
        _registerRemoteIdentityFromCentralLink(hello, key);
      }

      // Say hello back down the new link.
      await _sendFramesToCentral(link, _helloCache);
      // Advertise our v2 DM pre-key so the peer can send forward-secret DMs.
      if (_preKeyAnnounceCache.isNotEmpty) {
        await _sendFramesToCentral(link, _preKeyAnnounceCache);
      }
    } on Object catch (e) {
      SafeLog.error('mesh', 'link establishment failed', e);
      _centralLinks.remove(key);
      try {
        await _central.disconnect(peripheral);
      } on Object catch (e2) {
        SafeLog.error('mesh', 'cleanup disconnect failed', e2);
      }
    }
  }

  void _onCentralConnectionState(PeripheralConnectionStateChangedEventArgs e) {
    if (e.state != ConnectionState.connected) {
      _dropPeerForLink(e.peripheral.uuid.toString());
    }
  }

  void _onCharacteristicNotified(GATTCharacteristicNotifiedEventArgs e) {
    final String key = e.peripheral.uuid.toString();
    unawaited(_pushCentralFrame(key, e.value));
  }

  Future<void> _pushCentralFrame(String key, Uint8List frame) async {
    final _CentralLink? link = _centralLinks[key];
    if (link == null) {
      return;
    }
    final Uint8List? packet = _centralFrames.push(frame);
    if (packet != null) {
      await _handlePacket(packet);
    }
  }

  Future<int?> _safeMaxWriteLength(Peripheral peripheral) async {
    try {
      return await _central.getMaximumWriteLength(
        peripheral,
        type: GATTCharacteristicWriteType.withResponse,
      );
    } on Object catch (e) {
      SafeLog.error('mesh', 'getMaximumWriteLength failed', e);
      return null;
    }
  }

  GATTService? _findService(List<GATTService> services) {
    for (final GATTService s in services) {
      if (s.uuid.toString().toUpperCase() ==
          BleConstants.serviceUuid.toUpperCase()) {
        return s;
      }
    }
    return null;
  }

  GATTCharacteristic? _findChar(GATTService service, String uuid) {
    final String needle = uuid.toUpperCase();
    for (final GATTCharacteristic c in service.characteristics) {
      if (c.uuid.toString().toUpperCase() == needle) {
        return c;
      }
    }
    return null;
  }
// -------------------------------------------------------- peripheral role

  void _onWriteRequested(GATTCharacteristicWriteRequestedEventArgs e) {
    final GATTWriteRequest request = e.request;
    // Every write gets an explicit response — never leave a caller hanging.
    unawaited(
      _peripheral.respondWriteRequest(request).catchError((Object err) {
        SafeLog.error('mesh', 'respondWriteRequest failed', err);
      }),
    );
    final Uint8List frame = request.value;
    if (!_isSaneFrame(frame)) {
      SafeLog.info('mesh', 'peripheral dropped inbound frame');
      return;
    }
    final Uint8List? packet = _peripheralFrames.push(frame);
    if (packet != null) {
      unawaited(_handlePacket(packet, fromCentral: e.central));
    }
  }

  void _onReadRequested(GATTCharacteristicReadRequestedEventArgs e) {
    if (e.characteristic.uuid.toString().toUpperCase() ==
        BleConstants.identityCharUuid.toUpperCase()) {
      final Uint8List hello =
          _helloCache.isEmpty ? Uint8List(0) : Uint8List.fromList(_helloCache);
      if (hello.isEmpty) {
        unawaited(
          _peripheral
              .respondReadRequestWithError(
            e.request,
            error: GATTError.unlikelyError,
          )
              .catchError((Object err) {
            SafeLog.error('mesh', 'read error response failed', err);
          }),
        );
        return;
      }
      unawaited(
        _peripheral
            .respondReadRequestWithValue(e.request, value: hello)
            .catchError((Object err) {
          SafeLog.error('mesh', 'read response failed', err);
        }),
      );
      return;
    }
    unawaited(
      _peripheral
          .respondReadRequestWithError(
        e.request,
        error: GATTError.attributeNotFound,
      )
          .catchError((Object err) {
        SafeLog.error('mesh', 'read error response failed', err);
      }),
    );
  }

  void _onPeripheralConnectionState(CentralConnectionStateChangedEventArgs e) {
    final String key = e.central.uuid.toString();
    if (e.state != ConnectionState.connected) {
      _peripheralLinks.remove(key);
      _dropPeerForLink(key);
    }
  }

  bool _isSaneFrame(Uint8List frame) {
    // Magical prefix + opcode + counters + payload; anything else is hostile.
    if (frame.length < 6) {
      return false;
    }
    if (frame[0] != BleConstants.magicByte0 ||
        frame[1] != BleConstants.magicByte1) {
      return false;
    }
    if (frame[2] != BleConstants.frameOpData) {
      return false;
    }
    return true;
  }

  // ----------------------------------------------------------- peer registry

  /// Register a remote identity from the central role (keyed link util).
  void _registerRemoteIdentityFromCentralLink(
    HelloIdentity hello,
    String linkKey,
  ) {
    final String peerId = _peerIdFor(hello);
    final String shortId = _shortIdFor(hello);
    final Peer peer = _upsertPeerState(
      peerId: peerId,
      shortId: shortId,
      displayName: hello.displayName,
      signPublicKey: hello.signPublicKey,
      dhPublicKey: hello.dhPublicKey,
    );
    final _CentralLink? link = _centralLinks[linkKey];
    if (link != null) {
      link.ownerShortId = shortId;
      link.peerId = peerId;
    } else {
      _removeIfEmpty(peer);
    }
    notifyListeners();
  }

  /// Register a remote identity from an inbound hello packet written by a
  /// connected central (peripheral role).
  void _registerRemoteIdentityFromCentral(
    HelloIdentity hello,
    Central central,
  ) {
    final String key = central.uuid.toString();
    final String peerId = _peerIdFor(hello);
    final String shortId = _shortIdFor(hello);
    final Peer peer = _upsertPeerState(
      peerId: peerId,
      shortId: shortId,
      displayName: hello.displayName,
      signPublicKey: hello.signPublicKey,
      dhPublicKey: hello.dhPublicKey,
    );
    _peerIdByShortId[shortId] = peerId;
    _onlinePeers[peerId] = peer;
    _peripheralLinks[key] = _PeripheralLink(
      central: central,
      ownerShortId: shortId,
      peerId: peerId,
    );
    notifyListeners();
  }

  String _peerIdFor(HelloIdentity hello) {
    return base64Encode(<int>[...hello.signPublicKey, ...hello.dhPublicKey]);
  }

  String _shortIdFor(HelloIdentity hello) {
    final Uint8List combined = Uint8List(64);
    combined.setAll(0, hello.signPublicKey);
    combined.setAll(32, hello.dhPublicKey);
    return shortToHex(combined);
  }

  Peer _upsertPeerState({
    required String peerId,
    required String shortId,
    required String displayName,
    required Uint8List signPublicKey,
    required Uint8List dhPublicKey,
  }) {
    final Peer? existing = LocalVault.peerById(peerId);
    final DateTime now = DateTime.now();
    final Peer peer = Peer(
      id: peerId,
      displayName: SafeInput.sanitizeName(displayName),
      signPublicKey: signPublicKey,
      dhPublicKey: dhPublicKey,
      shortId: shortId,
      firstSeenAt: existing?.firstSeenAt ?? now,
      lastSeenAt: now,
      isOnline: true,
    );
    unawaited(LocalVault.upsertPeer(peer));
    _peerIdByShortId[shortId] = peerId;
    _onlinePeers[peerId] = peer;
    return peer;
  }

  void _removeIfEmpty(Peer peer) {
    if (!_onlinePeers.containsKey(peer.id)) {
      return;
    }
    final bool used = _centralLinks.values.any(
      (_CentralLink l) => l.peerId == peer.id,
    );
    if (!used) {
      _onlinePeers.remove(peer.id);
    }
  }

  void _dropPeerForLink(String linkKey) {
    final String? centralPeer = _centralLinks.remove(linkKey)?.peerId;
    if (centralPeer != null) {
      _markOffline(centralPeer);
      return;
    }
    final String? peripheralPeer = _peripheralLinks.remove(linkKey)?.peerId;
    if (peripheralPeer != null) {
      _markOffline(peripheralPeer);
    }
  }

  void _markOffline(String peerId) {
    final Peer? peer = _onlinePeers.remove(peerId);
    if (peer != null) {
      unawaited(
        LocalVault.upsertPeer(peer.copyWith(isOnline: false)),
      );
      notifyListeners();
    }
  }

  Future<void> refreshPresence() async {
    try {
      await _central.stopDiscovery();
    } on Object catch (e) {
      SafeLog.error('mesh', 'stopDiscovery on refresh failed', e);
    }
    await _startScan();
    notifyListeners();
  }

  String get myFriendlyCode {
    final String short = _myShortId;
    return short.length >= 6 ? short.substring(short.length - 6) : short;
  }

  /// Public self-portrait used for the QR card (public keys only).
  Peer? get selfPeer {
    final IdentityMaterial? identity = _identity;
    if (identity == null) {
      return null;
    }
    final DateTime now = DateTime.now();
    return Peer(
      id: base64Encode(<int>[...identity.signPublic, ...identity.dhPublic]),
      displayName: identity.displayName,
      signPublicKey: identity.signPublic,
      dhPublicKey: identity.dhPublic,
      shortId: _myShortId,
      firstSeenAt: now,
      lastSeenAt: now,
      isOnline: true,
    );
  }

  // ------------------------------------------------------------ packet flow

  Future<void> _handlePacket(
    Uint8List packet, {
    Central? fromCentral,
  }) async {
    try {
      await _dispatchPacket(packet, fromCentral: fromCentral);
    } on Object catch (e) {
      // A malformed or hostile packet must never escape as an unhandled async
      // error and kill the listener that carried it.
      SafeLog.error('mesh', 'packet handling failed', e);
    }
  }

  Future<void> _dispatchPacket(
    Uint8List packet, {
    Central? fromCentral,
  }) async {
    if (packet.isEmpty || !SafeInput.knowOpcode(packet[0])) {
      SafeLog.info('mesh', 'unknown opcode dropped');
      return;
    }
    switch (packet[0]) {
      case Opcodes.identity:
        if (fromCentral == null) {
          return; // hello already handled via identity read on our side
        }
        try {
          final HelloIdentity? hello = await parseHello(packet);
          if (hello != null) {
            _registerRemoteIdentityFromCentral(hello, fromCentral);
          }
        } on FormatException catch (e) {
          SafeLog.info('mesh', 'hello rejected: $e');
        }
      case Opcodes.message:
        await _handleMessageEnvelope(packet, fromCentral: fromCentral);
      case Opcodes.heartbeat:
      // v1: presence rides on link state — nothing extra to do.
    }
  }

  Future<void> _handleMessageEnvelope(
    Uint8List packet, {
    Central? fromCentral,
  }) async {
    final ParsedMessageEnvelope? env;
    try {
      env = MessageEnvelopeCodec.parse(packet);
    } on FormatException catch (e) {
      SafeLog.info('mesh', 'bad envelope dropped: $e');
      return;
    }
    if (env == null) {
      return;
    }
    // Flood guard — each message id is honored only once per 90s.
    if (!_centralFrames.markSeen(env.dedupKey, DateTime.now())) {
      return;
    }

    // Public pre-key card — not a chat message; record + ack, never store.
    if (env.isPreKeyAnnounce) {
      await _handlePreKeyAnnounce(env, fromCentral);
      return;
    }

    final String? senderPeerId = _peerIdByShortId[env.fromShortId];
    if (senderPeerId == null) {
      SafeLog.info('mesh', 'message from unpaired shortId ignored');
      return;
    }
    final Peer? sender =
        _onlinePeers[senderPeerId] ?? LocalVault.peerById(senderPeerId);
    if (sender == null) {
      return;
    }
    if (_identity == null) {
      return;
    }
    final IdentityMaterial identity = _identity!;

    final bool isBroadcast = env.kind == MessageKinds.broadcast;
    final bool addressedToUs = env.toShortId == _myShortId;
    if (!isBroadcast && !addressedToUs) {
      // Direct message for another node — forward if we know that peer.
      await _relayDirect(env);
      return;
    }

    String? text;
    if (env.isDirectV2) {
      try {
        text = await _openDmV2(env, sender, identity);
      } on Object catch (e) {
        SafeLog.error('mesh', 'v2 open failed; envelope dropped', e);
        text = null;
      }
    } else {
      final Uint8List sessionKey = await TeaCrypto.deriveSessionKey(
        myDhPair: identity.dhKeyPair,
        theirDhPub: sender.dhPublicKey,
        myDhPub: identity.dhPublic,
      );
      text = await TeaCrypto.openText(
        key: sessionKey,
        sealed: env.sealedBody,
      );
    }
    if (text == null) {
      SafeLog.info('mesh', 'envelope undecryptable for us; not storing');
      return;
    }
    final String threadId =
        isBroadcast ? MeshService.neighborhoodThread : senderPeerId;
    final String messageId = await LocalVault.saveMessage(
      threadId: threadId,
      isOutgoing: false,
      kind: isBroadcast ? MessageKinds.broadcast : MessageKinds.direct,
      fromShortId: env.fromShortId,
      toShortId: env.toShortId,
      text: text,
      status: 'delivered',
    );
    _events.add(MeshUiEvent.incoming(threadId, messageId));
    notifyListeners();

    if (_relayEnabled && isBroadcast && env.hopLimit > 1) {
      await _relayBroadcast(env, senderPeerId, text, identity);
    }
  }

  /// Record a peer's public pre-key from its announcement and, when we are the
  /// peripheral on that link, answer with ours so pre-keys flow both ways.
  Future<void> _handlePreKeyAnnounce(
    ParsedMessageEnvelope env,
    Central? fromCentral,
  ) async {
    final String? peerId = _peerIdByShortId[env.fromShortId];
    final Uint8List? pub = env.escrowPub;
    final int? epoch = env.preKeyEpoch;
    if (peerId == null || pub == null || pub.length != 32 || epoch == null) {
      return;
    }
    final Peer? existing = _onlinePeers[peerId] ?? LocalVault.peerById(peerId);
    if (existing == null) {
      return;
    }
    final Peer updated = Peer(
      id: existing.id,
      displayName: existing.displayName,
      signPublicKey: existing.signPublicKey,
      dhPublicKey: existing.dhPublicKey,
      shortId: existing.shortId,
      firstSeenAt: existing.firstSeenAt,
      lastSeenAt: existing.lastSeenAt,
      isOnline: existing.isOnline,
      preKeyPublic: pub,
      preKeyEpoch: epoch,
    );
    _onlinePeers[peerId] = updated;
    unawaited(LocalVault.upsertPeer(updated));
    if (fromCentral != null) {
      final String key = fromCentral.uuid.toString();
      final _PeripheralLink? link = _peripheralLinks[key];
      if (link != null && _preKeyAnnounceCache.isNotEmpty) {
        unawaited(_sendFramesToPeripheral(link, _preKeyAnnounceCache));
      }
    }
  }

  /// Forward a broadcast to every online neighbor except the sender.
  Future<void> _relayBroadcast(
    ParsedMessageEnvelope env,
    String excludePeerId,
    String text,
    IdentityMaterial identity,
  ) async {
    if (!_relayEnabled) {
      return;
    }
    for (final Peer neighbor in _onlinePeers.values.toList(growable: false)) {
      if (neighbor.id == excludePeerId) {
        continue;
      }
      final Uint8List sessionKey = await TeaCrypto.deriveSessionKey(
        myDhPair: identity.dhKeyPair,
        theirDhPub: neighbor.dhPublicKey,
        myDhPub: identity.dhPublic,
      );
      final Uint8List resealed = await TeaCrypto.sealText(
        key: sessionKey,
        text: text,
      );
      final List<int> rebuilt = MessageEnvelopeCodec.build(
        msgId: env.msgId,
        kind: env.kind,
        hopLimit: env.hopLimit - 1,
        fromShortId: env.fromShortId,
        toShortId: '',
        utcMs: env.utcMs,
        sealedBody: resealed,
      );
      await _sendPacketTo(neighbor.id, Uint8List.fromList(rebuilt));
    }
  }

  /// Forward a direct (private) message one hop toward its recipient.
  Future<void> _relayDirect(ParsedMessageEnvelope env) async {
    if (!_relayEnabled) {
      return;
    }
    if (env.hopLimit <= 1) {
      return;
    }
    final String? peerId = _peerIdByShortId[env.toShortId];
    if (peerId == null) {
      return;
    }
    final List<int> rebuilt = MessageEnvelopeCodec.build(
      msgId: env.msgId,
      kind: env.kind,
      hopLimit: env.hopLimit - 1,
      fromShortId: env.fromShortId,
      toShortId: env.toShortId,
      utcMs: env.utcMs,
      sealedBody: env.sealedBody,
    );
    await _sendPacketTo(peerId, Uint8List.fromList(rebuilt));
  }

  // --------------------------------------------------------- v2 DM crypto

  Future<Uint8List> _buildPreKeyAnnounce() async {
    final PreKey preKey = await DmSessionStore.rotatePreKey();
    return Uint8List.fromList(
      MessageEnvelopeCodec.build(
        msgId: TeaCrypto.randomBytes(16),
        kind: MessageKinds.preKeyAnnounce,
        hopLimit: 1,
        fromShortId: _myShortId,
        toShortId: '',
        utcMs: DateTime.now().millisecondsSinceEpoch,
        sealedBody: Uint8List(0),
        escrowPub: preKey.publicKey,
        preKeyEpoch: preKey.epoch,
      ),
    );
  }

  /// Seal one direct message with the v2 forward-secret X3DH + chain ratchet.
  /// Returns null when the peer has not announced a pre-key yet (the caller
  /// then falls back to the legacy deterministic-session seal).
  Future<_V2SealResult?> _sealDmV2({
    required String text,
    required Peer to,
    required IdentityMaterial identity,
  }) async {
    final Uint8List? prePub = to.preKeyPublic;
    final int preEpoch = to.preKeyEpoch;
    if (prePub == null || prePub.length != 32) {
      return null;
    }
    if (!DmSessionStore.isOpen) {
      // v2 needs the encrypted session store; without it we fall back to the
      // legacy sealed session rather than dropping the message.
      return null;
    }
    final OutboundDmState? state = await DmSessionStore.loadOutbound(to.id);
    late OutboundDmState use;
    if (state == null || state.theirPreKeyEpoch != preEpoch) {
      final SimpleKeyPair eph = await TeaCrypto.newEphemeralDhPair();
      final Uint8List ephPriv = await TeaCrypto.keyPairBytes(eph);
      final Uint8List ephPub = await TeaCrypto.publicKeyBytes(eph);
      final Uint8List root = await TeaCrypto.deriveDmRoot(
        myStaticPair: identity.dhKeyPair,
        myEphemeralPair: eph,
        theirPreKeyPub: prePub,
        theirStaticPub: to.dhPublicKey,
      );
      final Uint8List chain =
          await TeaCrypto.dmDirectionChain(root: root, initiator: true);
      use = OutboundDmState(
        ephemeralPriv: ephPriv,
        ephemeralPub: ephPub,
        theirPreKeyEpoch: preEpoch,
        chainKey: chain,
        nextIndex: 0,
      );
    } else {
      use = state;
    }
    final DmRatchetStep step = await TeaCrypto.dmRatchetStep(
        chainKey: use.chainKey, step: use.nextIndex);
    final Uint8List sealedBody =
        await TeaCrypto.sealText(key: step.messageKey, text: text);
    return _V2SealResult(
      sealedBody: sealedBody,
      escrowPub: use.ephemeralPub,
      dmIndex: use.nextIndex,
      preKeyEpoch: use.theirPreKeyEpoch,
      nextChainKey: step.nextChainKey,
      baseState: use,
    );
  }

  /// Open a v2 direct message for us, advancing the inbound ratchet and the
  /// skip window only after the AEAD tag verifies. Returns null on any
  /// failure (wrong pre-key, replayed index, tamper, hostile chain index).
  Future<String?> _openDmV2(
    ParsedMessageEnvelope env,
    Peer sender,
    IdentityMaterial identity,
  ) async {
    final Uint8List? escrow = env.escrowPub;
    final int? index = env.dmIndex;
    final int? epoch = env.preKeyEpoch;
    if (!DmSessionStore.isOpen) {
      return null;
    }
    if (escrow == null ||
        escrow.length != 32 ||
        index == null ||
        epoch == null) {
      return null;
    }
    final PreKey? preKey = await DmSessionStore.preKeyForEpoch(epoch);
    if (preKey == null) {
      return null; // we rotated away the epoch long ago (or hostile value)
    }
    final InboundDmState? loaded = await DmSessionStore.loadInbound(sender.id);
    final bool sameSession = loaded != null &&
        loaded.myPreKeyEpoch == epoch &&
        _bytesEqual(loaded.theirEphPub, escrow);

    if (sameSession) {
      final InboundDmState current = loaded;
      if (index < current.recvN) {
        // Out-of-order straggler left behind by an earlier fast-forward.
        final Uint8List? lateKey = current.skipped[index];
        if (lateKey == null) {
          return null; // too old — outside the bounded skip window
        }
        final String? lateText =
            await TeaCrypto.openText(key: lateKey, sealed: env.sealedBody);
        if (lateText == null) {
          return null; // tag mismatch — never mix keys
        }
        final Map<int, Uint8List> pruned = <int, Uint8List>{};
        for (final MapEntry<int, Uint8List> e in current.skipped.entries) {
          if (e.key != index) {
            pruned[e.key] = e.value;
          }
        }
        await DmSessionStore.saveInbound(
          sender.id,
          InboundDmState(
            theirEphPub: current.theirEphPub,
            myPreKeyEpoch: current.myPreKeyEpoch,
            recvChainKey: current.recvChainKey,
            recvN: current.recvN,
            skipped: pruned,
          ),
        );
        return lateText;
      }
      final DmWalkResult walk;
      try {
        walk = await DmRatchet.walk(
          chainKey: current.recvChainKey,
          fromIndex: current.recvN,
          toIndex: index,
        );
      } on FormatException {
        return null; // hostile index — never trust the wire
      }
      final String? text = await TeaCrypto.openText(
          key: walk.messageKey, sealed: env.sealedBody);
      if (text == null) {
        return null;
      }
      final InboundDmState advanced = current.advanced(
        chain: walk.nextChainKey,
        next: index + 1,
        added: walk.intermediates,
      );
      await DmSessionStore.saveInbound(sender.id, advanced);
      return text;
    }

    // Brand-new session initiated by the sender.
    final SimpleKeyPair preKeyPair =
        await TeaCrypto.dhPairFromSeed(preKey.seed);
    final Uint8List root = await TeaCrypto.deriveDmRoot(
      myStaticPair: identity.dhKeyPair,
      myEphemeralPair: preKeyPair,
      theirPreKeyPub: escrow,
      theirStaticPub: sender.dhPublicKey,
    );
    final Uint8List chain =
        await TeaCrypto.dmDirectionChain(root: root, initiator: true);
    final DmWalkResult walk;
    try {
      walk =
          await DmRatchet.walk(chainKey: chain, fromIndex: 0, toIndex: index);
    } on FormatException {
      return null; // hostile index — never trust the wire
    }
    final String? text =
        await TeaCrypto.openText(key: walk.messageKey, sealed: env.sealedBody);
    if (text == null) {
      return null;
    }
    final InboundDmState advanced = InboundDmState.fresh(
      theirEphPub: Uint8List.fromList(escrow),
      myPreKeyEpoch: epoch,
      recvChainKey: walk.nextChainKey,
      openedThrough: index + 1,
    ).advanced(
      chain: walk.nextChainKey,
      next: index + 1,
      added: walk.intermediates,
    );
    await DmSessionStore.saveInbound(sender.id, advanced);
    return text;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<bool> _sendPacketTo(String peerId, Uint8List packet) async {
    for (final _CentralLink link in _centralLinks.values) {
      if (link.peerId == peerId) {
        try {
          await _sendFramesToCentral(link, packet);
          return true;
        } on Object catch (e) {
          SafeLog.error('mesh', 'write to central link failed', e);
          return false;
        }
      }
    }
    for (final _PeripheralLink link in _peripheralLinks.values) {
      if (link.peerId == peerId) {
        try {
          await _sendFramesToPeripheral(link, packet);
          return true;
        } on Object catch (e) {
          SafeLog.error('mesh', 'notify to peripheral link failed', e);
          return false;
        }
      }
    }
    return false;
  }

  Future<void> _sendFramesToCentral(_CentralLink link, Uint8List packet) async {
    final GATTCharacteristic? writeChar = link.writeChar;
    final Fragmenter? fragmenter = link.fragmenter;
    if (writeChar == null || fragmenter == null) {
      return;
    }
    final List<Uint8List> frames = fragmenter.framePacket(
      link.seq++ & 0xFF,
      packet,
    );
    for (final Uint8List frame in frames) {
      await _central.writeCharacteristic(
        link.peripheral,
        writeChar,
        value: frame,
        type: GATTCharacteristicWriteType.withResponse,
      );
    }
  }

  Future<void> _sendFramesToPeripheral(
    _PeripheralLink link,
    Uint8List packet,
  ) async {
    final GATTCharacteristic? notifyChar = _localNotifyChar;
    if (notifyChar == null) {
      return;
    }
    final Fragmenter fragmenter = link.fragmenter;
    final List<Uint8List> frames = fragmenter.framePacket(
      link.seq++ & 0xFF,
      packet,
    );
    for (final Uint8List frame in frames) {
      await _peripheral.notifyCharacteristic(
        link.central,
        notifyChar,
        value: frame,
      );
    }
  }

  // ------------------------------------------------------------------ send

  /// Send a neighborhood broadcast to everyone currently in range.
  Future<SendResult> sendBroadcast(String rawText) async {
    final String text;
    try {
      text = SafeInput.sanitizeText(rawText);
    } on FormatException {
      return const SendResult(0, 0);
    }
    if (_identity == null) {
      return const SendResult(0, 0);
    }
    final IdentityMaterial identity = _identity!;
    final Uint8List msgId = TeaCrypto.randomBytes(16);
    final int utcMs = DateTime.now().millisecondsSinceEpoch;

    await LocalVault.saveMessage(
      threadId: MeshService.neighborhoodThread,
      isOutgoing: true,
      kind: 0,
      fromShortId: _myShortId,
      toShortId: '',
      text: text,
      status: _onlinePeers.isEmpty ? 'failed' : 'sending',
    );

    int delivered = 0;
    for (final Peer neighbor in _onlinePeers.values.toList(growable: false)) {
      final Uint8List sessionKey = await TeaCrypto.deriveSessionKey(
        myDhPair: identity.dhKeyPair,
        theirDhPub: neighbor.dhPublicKey,
        myDhPub: identity.dhPublic,
      );
      final Uint8List sealedBody = await TeaCrypto.sealText(
        key: sessionKey,
        text: text,
      );
      final List<int> envelope = MessageEnvelopeCodec.build(
        msgId: msgId,
        kind: 0,
        hopLimit: MessageLimits.maxHops,
        fromShortId: _myShortId,
        toShortId: '',
        utcMs: utcMs,
        sealedBody: sealedBody,
      );
      final bool ok = await _sendPacketTo(
        neighbor.id,
        Uint8List.fromList(envelope),
      );
      if (ok) {
        delivered++;
      }
    }
    notifyListeners();
    return SendResult(delivered, _onlinePeers.length);
  }

  /// Send a direct (private) message to one peer.
  Future<SendResult> sendDirect(String rawText, Peer to) async {
    final String text;
    try {
      text = SafeInput.sanitizeText(rawText);
    } on FormatException {
      return const SendResult(0, 0);
    }
    if (_identity == null) {
      return const SendResult(0, 0);
    }
    final IdentityMaterial identity = _identity!;
    final Uint8List msgId = TeaCrypto.randomBytes(16);
    final int utcMs = DateTime.now().millisecondsSinceEpoch;

    // v2 (forward-secret) first; fall back to the legacy deterministic
    // session only while the peer has not announced a pre-key yet.
    _V2SealResult? v2;
    try {
      v2 = await _sealDmV2(text: text, to: to, identity: identity);
    } on Object catch (e) {
      // Any fault inside the v2 path must never lose the message: fall back to
      // the legacy sealed session for this send.
      SafeLog.error('mesh', 'v2 seal failed; using legacy path', e);
      v2 = null;
    }
    final Uint8List sealedBody;
    final int kind;
    Uint8List? escrowPub;
    int dmIndex = 0;
    int preKeyEpoch = 0;
    if (v2 != null) {
      sealedBody = v2.sealedBody;
      kind = MessageKinds.directV2;
      escrowPub = v2.escrowPub;
      dmIndex = v2.dmIndex;
      preKeyEpoch = v2.preKeyEpoch;
    } else {
      final Uint8List sessionKey = await TeaCrypto.deriveSessionKey(
        myDhPair: identity.dhKeyPair,
        theirDhPub: to.dhPublicKey,
        myDhPub: identity.dhPublic,
      );
      sealedBody = await TeaCrypto.sealText(key: sessionKey, text: text);
      kind = MessageKinds.direct;
    }
    final List<int> envelope = MessageEnvelopeCodec.build(
      msgId: msgId,
      kind: kind,
      hopLimit: 1,
      fromShortId: _myShortId,
      toShortId: to.shortId,
      utcMs: utcMs,
      sealedBody: sealedBody,
      escrowPub: escrowPub,
      dmIndex: dmIndex,
      preKeyEpoch: preKeyEpoch,
    );
    final bool sent = await _sendPacketTo(to.id, Uint8List.fromList(envelope));
    if (v2 != null && sent) {
      // Advance the outbound chain only once the packet left on the radio.
      await DmSessionStore.saveOutbound(
        to.id,
        v2.baseState.advance(v2.nextChainKey),
      );
    }
    await LocalVault.saveMessage(
      threadId: to.id,
      isOutgoing: true,
      kind: 1,
      fromShortId: _myShortId,
      toShortId: to.shortId,
      text: text,
      status: sent ? 'sent' : 'failed',
    );
    notifyListeners();
    return SendResult(sent ? 1 : 0, 1);
  }

  @override
  void dispose() {
    _tornDown = true;
    unawaited(_events.close());
    super.dispose();
  }

  /// Teardown of the radios and all in-memory mesh state.
  ///
  /// Unlike [dispose] this is *reversible*: [start] can bring the mesh back up
  /// in the same process, which the destructive-erase flow needs because it
  /// drops straight back into onboarding. The event sink stays open so UI
  /// listeners survive the cycle.
  Future<void> shutdown() async {
    if (_tornDown) {
      return;
    }
    try {
      await _central.stopDiscovery();
    } on Object catch (e) {
      SafeLog.error('mesh', 'stopDiscovery during teardown', e);
    }
    try {
      await _peripheral.stopAdvertising();
    } on Object catch (e) {
      SafeLog.error('mesh', 'stopAdvertising during teardown', e);
    }
    _scanning = false;
    _advertising = false;
    _centralLinks.clear();
    _peripheralLinks.clear();
    _peerIdByShortId.clear();
    _onlinePeers.clear();
    _identity = null;
    _helloCache = Uint8List(0);
    _preKeyAnnounceCache = Uint8List(0);
    _myShortId = '';
    notifyListeners();
  }
}

class SendResult {
  const SendResult(this.delivered, this.total);

  final int delivered;
  final int total;
}

/// Result of one v2 DM seal: the ciphertext plus everything the envelope
/// needs, and the chain transition to commit after a successful send.
class _V2SealResult {
  const _V2SealResult({
    required this.sealedBody,
    required this.escrowPub,
    required this.dmIndex,
    required this.preKeyEpoch,
    required this.nextChainKey,
    required this.baseState,
  });

  final Uint8List sealedBody;
  final Uint8List escrowPub;
  final int dmIndex;
  final int preKeyEpoch;
  final Uint8List nextChainKey;
  final OutboundDmState baseState;
}

/// Events surfaced to the UI (never carries plaintext).
class MeshUiEvent {
  MeshUiEvent.incoming(this.threadId, this.messageId) : type = 1;

  final String threadId;
  final String messageId;
  final int type;
}

class _CentralLink {
  _CentralLink(this.peripheral);

  final Peripheral peripheral;
  GATTCharacteristic? writeChar;
  GATTCharacteristic? notifyChar;
  Fragmenter? fragmenter;
  String? ownerShortId;
  String? peerId;
  int seq = 0;
  int writeMtu = BleConstants.preferredMtu;
}

class _PeripheralLink {
  _PeripheralLink({
    required this.central,
    required this.ownerShortId,
    required this.peerId,
    Fragmenter? fragmenter,
  }) : fragmenter = fragmenter ?? const _Default160();

  final Central central;
  final String ownerShortId;
  final String peerId;
  final Fragmenter fragmenter;
  int seq = 0;
}

class _Default160 extends Fragmenter {
  const _Default160() : super(160);
}
