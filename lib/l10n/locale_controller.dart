import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_strings.dart';

/// Owns the UI language: one toggle anywhere, every screen follows.
///
/// The choice persists in secure storage (the app has no other store by
/// design — nothing is written outside the vault's keychain), and flips
/// [AppStrings.language] so all static getters resolve in the new tongue.
class LocaleController extends ChangeNotifier {
  LocaleController._();

  static LocaleController? _instance;

  static LocaleController getInstance() => _instance ??= LocaleController._();

  static const String _storageKey = 'app.lang';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  AppLang _lang = AppLang.ar;

  AppLang get lang => _lang;

  /// Read the persisted choice (called once, before the first frame).
  Future<void> load() async {
    try {
      final String? saved = await _storage.read(key: _storageKey);
      if (saved == AppLang.en.name) {
        _lang = AppLang.en;
        AppStrings.language = _lang;
      } else if (saved == AppLang.ar.name) {
        _lang = AppLang.ar;
        AppStrings.language = _lang;
      }
    } on Object {
      // Secure storage unavailable: Arabic stays the default.
    }
    notifyListeners();
  }

  /// Switch the UI language and persist it.
  Future<void> setLang(AppLang lang) async {
    if (lang == _lang) {
      return;
    }
    _lang = lang;
    AppStrings.language = lang;
    notifyListeners();
    try {
      await _storage.write(key: _storageKey, value: lang.name);
    } on Object {
      // Persistence is best-effort; the session choice already applied.
    }
  }
}
