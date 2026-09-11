import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/utils/qr_payload.dart';
import '../../l10n/app_strings.dart';
import '../../mesh/protocol.dart';
import '../../models/peer.dart';
import '../../storage/local_vault.dart';
import '../../theme/app_palette.dart';

/// Scan a friend's card. Only public keys are read; nothing is uploaded.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw == null) {
        continue;
      }
      final QrIdentity? identity = QrPayload.parse(raw);
      if (identity == null) {
        _flash(AppStrings.invalidQr);
        continue;
      }
      _handled = true;
      _askToSave(identity);
      return;
    }
  }

  Future<void> _askToSave(QrIdentity identity) async {
    final String? alias = await _confirmAlias(identity);
    if (alias == null || !mounted) {
      return; // user cancelled
    }
    final DateTime now = DateTime.now();
    final Uint8List combined = Uint8List(64);
    combined.setAll(0, identity.signPublicKey);
    combined.setAll(32, identity.dhPublicKey);
    final String peerId = base64Encode(combined);
    final String shortId = shortToHex(combined);

    final Peer peer = Peer(
      id: peerId,
      displayName: alias,
      signPublicKey: identity.signPublicKey,
      dhPublicKey: identity.dhPublicKey,
      shortId: shortId,
      firstSeenAt: now,
      lastSeenAt: now,
    );
    await LocalVault.upsertPeer(peer);
    if (!mounted) {
      return;
    }
    _flash('${AppStrings.scannedFriend}: $alias');
    Navigator.of(context).pop();
  }

  Future<String?> _confirmAlias(QrIdentity identity) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final TextEditingController alias =
            TextEditingController(text: identity.displayName);
        return AlertDialog(
          backgroundColor: AppPalette.lapisHigh,
          title: const Text(AppStrings.pairingIdHint),
          content: TextField(
            controller: alias,
            autofocus: true,
            decoration: const InputDecoration(hintText: AppStrings.nameHint),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(AppStrings.cancel),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(alias.text.trim()),
              child: const Text(AppStrings.continueGold),
            ),
          ],
        );
      },
    );
  }

  void _flash(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.scanFriend)),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (BuildContext context, MobileScannerException error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(
                    Icons.no_photography_outlined,
                    size: 52,
                    color: AppPalette.brass,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppStrings.cameraPermissionDenied,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        },
        overlayBuilder: (BuildContext context, BoxConstraints constraints) {
          return Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppPalette.gold,
                  width: 2.4,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          );
        },
      ),
    );
  }
}