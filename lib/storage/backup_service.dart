import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../core/crypto/tea_crypto.dart';
import '../core/utils/safe_log.dart';
import 'local_vault.dart';
import 'secure_identity_store.dart';

/// One-tap offline backup: everything in the Hive boxes is exported as a
/// JSON blob sealed with the install [dbKey]. Restore validates and imports.
class BackupService {
  BackupService._();

  static const String magic = 'SPILLTEA-BACKUP-1';

  static Future<String> exportArchive() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(
      '${dir.path}${Platform.pathSeparator}spill_the_tea_backup.json',
    );

    final Map<String, Object> payload = <String, Object>{
      'magic': magic,
      'createdMs': DateTime.now().millisecondsSinceEpoch,
      'peers': <Object>[],
      'messages': <Object>[],
      'meta': <Object>[],
    };
    for (final Box<Map> box in <Box<Map>>[
      Hive.box<Map>(LocalVault.peersBoxName),
      Hive.box<Map>(LocalVault.messagesBoxName),
      Hive.box<Map>(LocalVault.metaBoxName),
    ]) {
      final List<Object> entries = <Object>[];
      for (final Map? value in box.values) {
        if (value != null) {
          entries.add(jsonDecode(jsonEncode(value)));
        }
      }
      if (box.name == LocalVault.peersBoxName) {
        payload['peers'] = entries;
      } else if (box.name == LocalVault.messagesBoxName) {
        payload['messages'] = entries;
      } else {
        payload['meta'] = entries;
      }
    }

    final Uint8List dbKey = await SecureIdentityStore.loadOrCreateDbKey();
    final Uint8List sealed = await TeaCrypto.sealText(
      key: dbKey,
      text: jsonEncode(payload),
    );
    await file.writeAsBytes(sealed, flush: true);
    return file.path;
  }

  static Future<int> importArchive(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('archive file not found');
    }
    final Uint8List sealed = await file.readAsBytes();
    final Uint8List dbKey = await SecureIdentityStore.loadOrCreateDbKey();
    final String? plain = await TeaCrypto.openText(key: dbKey, sealed: sealed);
    if (plain == null) {
      throw StateError('unable to open archive (wrong key or corrupt)');
    }
    final Map<String, dynamic> payload =
        jsonDecode(plain) as Map<String, dynamic>;
    if (payload['magic'] != magic) {
      throw const FormatException('not a صب الجاي archive');
    }
    final int imported = await _importIntoBox(payload);
    SafeLog.info('backup', 'imported $imported entries');
    return imported;
  }

  static Future<int> _importIntoBox(Map<String, dynamic> payload) async {
    int count = 0;
    final List<Box<Map>> boxes = <Box<Map>>[
      Hive.box<Map>(LocalVault.peersBoxName),
      Hive.box<Map>(LocalVault.messagesBoxName),
      Hive.box<Map>(LocalVault.metaBoxName),
    ];
    for (final Box<Map> box in boxes) {
      final List<Object> entries;
      if (box.name == LocalVault.peersBoxName) {
        entries = (payload['peers'] as List<Object>?) ?? const <Object>[];
      } else if (box.name == LocalVault.messagesBoxName) {
        entries = (payload['messages'] as List<Object>?) ?? const <Object>[];
      } else {
        entries = (payload['meta'] as List<Object>?) ?? const <Object>[];
      }
      for (final Object entry in entries) {
        if (entry is! Map) {
          continue; // malformed entry skipped, never trusted
        }
        final String? key = entry['id'] as String?;
        if (key == null || key.isEmpty) {
          continue;
        }
        await box.put(key, entry);
        count++;
      }
    }
    return count;
  }
}