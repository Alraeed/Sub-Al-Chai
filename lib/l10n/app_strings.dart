/// Lightweight bilingual strings for صب الجاي.
/// The app is Arabic-first with RTL forced; English is the fallback.
abstract final class AppStrings {
  static const String appName = 'صب الجاي';
  static const String appNameLatin = 'Spill the Tea';

  // Onboarding.
  static const String proverb = 'حياهم الله';
  static const String tagline = 'راسل احبابك بدوم نت';
  static const String onboardingIntro =
      'صب الجاي يخليك تصب الجاي و تسولف براحتك بدون سيرفرات، بدون إنترنت، بس بلوتوث.';
  static const String startBrewing = 'يلا، صبّ الجاي';
  static const String chooseDisplayName = 'شلون نصيحلك؟';
  static const String nameHint = 'اسمك (شلون الناس تصيحلك)';
  static const String continueGold = 'متابعة';

  // Home / mesh radar.
  static const String nearbyTitle = 'الجوار';
  static const String nearbySubtitle = 'منو يمك؟';
  static const String noNearby = 'محد يمك :(';
  static const String meshPulseActive = 'الشبكة فعّالة';
  static const String meshPulseInactive = 'الشبكة نايمة';
  static const String talkTo = 'احجي وياي';
  static const String peersOnline = 'متواجدين قريب';

  // Chat list.
  static const String chatsTitle = 'الدردشة';
  static const String emptyChats = 'ماكو سوالف';
  static const String emptyChatsHint =
      'سوي مسح للرمز او خخلي صاحبك قريب منك حتى تشبكون';
  static const String newChat = 'دردشة جديدة';

  // Chat screen.
  static const String chatHint = 'اكتب…';
  static const String send = 'إرسال';
  static const String messageByteLimit = 'الرسالة كلش طويلةو شوي اختصر';
  static const String peerLeft = 'صاحبك صار بعيد';
  static const String delivered = 'وصلت';
  static const String sending = 'ارسال...';
  static const String failed = 'ما وصلت';

  // QR.
  static const String myCard = 'رمزي';
  static const String myCardHint =
      'خلي صاحبك يمسح الرمز حتى يضيفك. لا بيانات حساسة تنتقل.';
  static const String scanFriend = 'امسح رمز صاحبك';
  static const String scanHint = 'امسح رمز صديقك';
  static const String scannedFriend = 'تم حفض الصديق';
  static const String invalidQr = 'الرمز غير صالح';
  static const String pairingIdHint = 'شنو تريد تسمي صاحبك؟';
  static const String cameraPermissionDenied =
      'نحتاج إذن الكاميرا حتى نمسح الرمز.';

  // Settings.
  static const String settingsTitle = 'الإعدادات';
  static const String myIdentity = 'هويتي';
  static const String friendlyCode = 'رمز الصداقة';
  static const String securitySection = 'السرية والأمان';
  static const String securityHint =
      'المفاتيح محفوظة بأمان (Android Keystore / iOS Keychain) وتشفّر كل رسالة ATT قبل ما تطلع من الجوال.';
  static const String backup = 'نسخ احتياطي';
  static const String backupExport = 'صدّر الأرشيف';
  static const String backupImport = 'استيراد الأرشيف';
  static const String eraseAll = 'امسح كل شيء';
  static const String eraseConfirm =
      'متأكد؟ كل الرسائل والهوية راح تُنمسح نهائياً.';
  static const String quitRelaying = 'أوقف الترحيل';
  static const String relayMode = 'الترحيل (نقل رسائل الجوار)';
  static const String relayOn = 'فعّل';
  static const String relayOff = 'أوقف';

  // Errors.
  static const String errorGeneric = 'صارت مشكلة, جرب مرة ثانية';
  static const String errorBluetoothOff = 'بلوتوث مطفي, شغله اول شي بعدين جرب';
  static const String errorBluetoothUnsupported = 'هذا الجهاز ما يدعم BLE';
  static const String errorPermissionDenied = 'ما نطيتنا الإذن للبلوتوث';
  static const String errorNoMessage = 'الرسالة فارغة, تريد ترسل امنياتك؟';

  static const String dangerZone = 'خطر';
  static const String done = 'تم';
  static const String cancel = 'إلغاء';
  static const String close = 'إغلاق';
}
