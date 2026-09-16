import 'dart:async';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/crypto/tea_crypto.dart';
import '../core/utils/safe_log.dart';
import '../core/utils/sanitizer.dart';
import '../mesh/mesh_service.dart';
import '../mesh/session_store.dart';
import '../storage/local_vault.dart';
import '../storage/secure_identity_store.dart';
import 'messaging_service.dart';

/// One-time app bootstrap: Hive, identity (create/load), DB key, mesh start.
class AppBootstrap extends ChangeNotifier {
  AppBootstrap._();

  static AppBootstrap? _instance;

  static AppBootstrap getInstance() {
    return _instance ??= AppBootstrap._();
  }

  bool ready = false;
  bool hasIdentity = false;
  String? displayName;

  Future<void> init() async {
    if (ready) {
      return;
    }
    try {
      await Hive.initFlutter();
      final Uint8List dbKey = await SecureIdentityStore.loadOrCreateDbKey();
      await LocalVault.open(dbKey);

      final IdentityMaterial? identity =
          await SecureIdentityStore.loadIdentity();
      if (identity != null) {
        hasIdentity = true;
        displayName = identity.displayName;
        unawaited(_startMesh(identity));
      }
    } on Object catch (e) {
      SafeLog.error('bootstrap', 'init failed', e);
    } finally {
      ready = true;
      notifyListeners();
    }
  }

  /// Create a fresh identity for this device (first launch).
  Future<bool> createIdentity(String rawName) async {
    final String name = SafeInput.sanitizeName(rawName);
    try {
      final SimpleKeyPair signPair = await TeaCrypto.newSignKeyPair();
      final SimpleKeyPair dhPair = await TeaCrypto.newDhKeyPair();
      final Uint8List signSeed = await TeaCrypto.keyPairBytes(signPair);
      final Uint8List dhPrivate = await TeaCrypto.keyPairBytes(dhPair);
      final Uint8List signPublic = await TeaCrypto.publicKeyBytes(signPair);
      final Uint8List dhPublic = await TeaCrypto.publicKeyBytes(dhPair);
      final IdentityMaterial identity = IdentityMaterial(
        displayName: name,
        signSeed: signSeed,
        dhPrivate: dhPrivate,
        signPublic: signPublic,
        dhPublic: dhPublic,
      );
      await SecureIdentityStore.saveIdentity(identity);
      displayName = name;
      hasIdentity = true;
      notifyListeners();
      unawaited(_startMesh(identity));
      return true;
    } on Object catch (e) {
      SafeLog.error('bootstrap', 'createIdentity failed', e);
      notifyListeners();
      return false;
    }
  }

  Future<void> _startMesh(IdentityMaterial identity) async {
    try {
      await MeshService.getInstance().start(identity: identity);
      MessagingService.getInstance().attach(MeshService.getInstance());
    } on Object catch (e) {
      SafeLog.error('bootstrap', 'mesh start failed', e);
    }
  }

  /// Wipe local data and identity, then restart the gate.
  Future<void> eraseEverything() async {
    try {
      await MeshService.getInstance().shutdown();
    } on Object catch (e) {
      SafeLog.error('bootstrap', 'mesh shutdown during erase', e);
    }
    try {
      // Rotating pre-keys and per-peer ratchet state live outside the message
      // vault; without this they would survive "erase everything".
      await DmSessionStore.wipe();
    } on Object catch (e) {
      SafeLog.error('bootstrap', 'dm session wipe failed', e);
    }
    try {
      await LocalVault.wipe();
    } on Object catch (e) {
      SafeLog.error('bootstrap', 'vault wipe failed', e);
    }
    try {
      await SecureIdentityStore.deleteIdentity();
    } on Object catch (e) {
      SafeLog.error('bootstrap', 'identity wipe failed', e);
    }
    try {
      // The vault must be usable again for the next identity: reopening it
      // here creates a fresh per-install key (the old one went with the
      // identity above).
      final Uint8List dbKey = await SecureIdentityStore.loadOrCreateDbKey();
      await LocalVault.open(dbKey);
    } on Object catch (e) {
      SafeLog.error('bootstrap', 'vault reopen after erase failed', e);
    }
    hasIdentity = false;
    displayName = null;
    notifyListeners();
  }
}
