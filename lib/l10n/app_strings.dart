import 'package:flutter/material.dart' show Locale;

/// Which language the UI is rendered in. Arabic is the brand's first
/// language; English is the full secondary.
enum AppLang { ar, en }

extension AppLangX on AppLang {
  Locale get locale => Locale(name);

  /// True when the UI should flow right-to-left.
  bool get isRtl => this == AppLang.ar;
}

/// Bilingual strings for صب الجاي.
///
/// Keys are static getters that read [AppStrings.language], so a call site
/// stays as plain `AppStrings.something`, flipping the language and
/// notifying listeners re-renders every screen in the new tongue.
abstract final class AppStrings {
  /// The active language. Defaults to Arabic; persisted by
  /// `LocaleController` and set at startup.
  static AppLang language = AppLang.ar;

  static bool get isArabic => language == AppLang.ar;

  // ---- brand (never translated, the lockup is intentionally bilingual).
  static const String appName = 'صب الجاي';
  static const String appNameLatin = 'Spill the Tea';

  // ---- onboarding.
  static const String proverb = 'حياهم الله';
  static String get tagline =>
      isArabic ? 'راسل احبابك بدوم نت' : 'Message your people, no internet';
  static String get onboardingIntro => isArabic
      ? 'صب الجاي يخليك تصب الجاي و تسولف براحتك بدون سيرفرات، بدون إنترنت، بس بلوتوث.'
      : 'Spill the Tea lets you talk freely. No servers, no internet, just Bluetooth between phones.';
  static String get startBrewing =>
      isArabic ? 'يلا، صبّ الجاي' : 'Pour the tea';
  static String get chooseDisplayName =>
      isArabic ? 'شلون نصيحلك؟' : 'What should we call you?';
  static String get nameHint => isArabic
      ? 'اسمك (شلون الناس تصيحلك)'
      : 'Your name (what people call you)';
  static String get continueGold => isArabic ? 'متابعة' : 'Continue';
  static String get worksFullyOfflineNote => isArabic
      ? 'iOS/Android · يعمل بدون إنترنت بالكامل'
      : 'iOS/Android · works fully offline';

  // ---- language switcher.
  static String get langSection => isArabic ? 'اللغة' : 'Language';
  static const String langAr = 'العربية';
  static const String langEn = 'English';

  // ---- how the app works.
  static String get howTitle =>
      isArabic ? 'شلون تشتغل التطبيق؟' : 'How the app works';
  static String get howStep1Title =>
      isArabic ? 'سوي هويتك' : 'Create your identity';
  static String get howStep1Body => isArabic
      ? 'اختر اسمك ومفاتيح التشفير تنولد على جوالك، ماكو شي يطلع للنت.'
      : 'Pick a name and your encryption keys are generated on this phone, nothing leaves it.';
  static String get howStep2Title =>
      isArabic ? 'امسح رمز صاحبك' : "Scan your friend's code";
  static String get howStep2Body => isArabic
      ? 'تبادلوا رموز الـ QR وجهاً بوجه حتى تتربطون، مفاتيح عامة بس.'
      : 'Exchange QR codes face to face to pair, public keys only.';
  static String get howStep3Title => isArabic ? 'سولف' : 'Start talking';
  static String get howStep3Body => isArabic
      ? 'رسائلك تطير من جوال لجوال بالبلوتوث، حتى اللي ورا بعض يدريهم.'
      : 'Messages fly phone to phone over Bluetooth, even around you.';

  // ---- how bluetooth messaging works.
  static String get btTitle => isArabic
      ? 'شلون يوصل التوصيل بالبلوتوث؟'
      : 'How Bluetooth messaging works';
  static List<String> get btPoints => isArabic
      ? <String>[
          'بدون إنترنت ولا سيرفرات، البلوتوث بس.',
          'الرسائل تقفز من جوال لجوال (شبكة الجوار) حتى توصل.',
          'كل رسالة مشفرة من طرف لطرف (AES-256-GCM).',
          'ماكو سيرفر أصلاً, يعني ماكو من يشوف رسائلك.',
        ]
      : <String>[
          'No internet, no servers, Bluetooth only.',
          'Messages hop phone to phone (a mesh) until they arrive.',
          'Every message is end-to-end encrypted (AES-256-GCM).',
          'There is no server at all, so no one can read your messages.',
        ];

  // ---- home / mesh radar.
  static String get nearbyTitle => isArabic ? 'الجوار' : 'Nearby';
  static String get nearbySubtitle =>
      isArabic ? 'منو يمك؟' : 'Who is around you?';
  static String get noNearby => isArabic ? 'محد يمك :(' : 'No one around :(';
  static String get meshPulseActive =>
      isArabic ? 'الشبكة فعّالة' : 'Mesh is awake';
  static String get meshPulseInactive =>
      isArabic ? 'الشبكة نايمة' : 'Mesh is asleep';
  static String get talkTo => isArabic ? 'احجي وياي' : 'Talk to me';
  static String get peersOnline => isArabic ? 'متواجدين قريب' : 'Online nearby';

  // ---- neighborhood map (radar).
  static String get mapTitle => isArabic ? 'خريطة الجوار' : 'Neighborhood map';
  static String get mapCaption => isArabic
      ? 'الخريطة تعرض حالة الاتصال، مو مكان. كل نقطة = شخص، والمواقع رمزية حسب الهوية.'
      : 'The map shows link state, not location. Each dot is a person; positions are symbolic, from identity.';
  static String get me => isArabic ? 'أنا (هذا الجهاز)' : 'Me (this device)';
  static String get linkedPeers => isArabic ? 'متصلين' : 'Linked';
  static String get awayPeers => isArabic ? 'شفتهم قبل' : 'Seen before';
  static String get reachTitle => isArabic ? 'التغطية' : 'Reach';
  static String get hiddenPeers => isArabic ? 'باقي' : 'Others';
  static String get relayActive => isArabic ? 'الترحيل شغال' : 'Relay on';
  static String get relayPaused => isArabic ? 'الترحيل موقف' : 'Relay paused';
  static String get scanningNow => isArabic ? 'يدوّر…' : 'Scanning…';
  static String get scanningAlone => isArabic
      ? 'لسه يدور… قرب من شخص أو امسح رمزه حتى يظهر.'
      : 'Still scanning… move closer to someone, or scan their code.';
  static String get radioOffHint => isArabic
      ? 'شغل البلوتوث حتى تعرف منو قريب منك وتوصلهم رسايلك.'
      : 'Turn Bluetooth on to see who is near and to deliver your messages.';
  static String get tryAgain => isArabic ? 'جرب مرة ثانية' : 'Try again';
  static String get aloneHint => isArabic
      ? 'لا أحد قريب… خلي البلوتوث شغال، أو امسح رمز صاحبك حتى يضاف لشبكتك.'
      : "No one nearby… keep Bluetooth on, or scan a friend's code to add them.";
  static String get hopSingular => isArabic ? 'قفزة' : 'hop';
  static String get hopDual => isArabic ? 'قفزتين' : '2 hops';
  static String get hopPlural => isArabic ? 'قفزات' : 'hops';
  static String get radarSummaryRadioOff => isArabic
      ? 'البلوتوث مطفي، الخريطة نايمة'
      : 'Bluetooth is off, the map is asleep';
  static String get radarSummaryAlone =>
      isArabic ? 'محد حولك، الخريطة فاضية' : 'No one around, the map is empty';
  static String get radarSummaryPrefix =>
      isArabic ? 'الخريطة تعرض:' : 'The map shows:';

  // ---- chat list.
  static String get chatsTitle => isArabic ? 'الدردشة' : 'Chats';
  static String get emptyChats => isArabic ? 'ماكو سوالف' : 'No chats yet';
  static String get emptyChatsHint => isArabic
      ? 'سوي مسح للرمز او خخلي صاحبك قريب منك حتى تشبكون'
      : 'Scan a code, or keep a friend close until you link up.';
  static String get newChat => isArabic ? 'دردشة جديدة' : 'New chat';
  static String get youPrefix => isArabic ? 'أنت: ' : 'You: ';

  // ---- chat screen.
  static String get chatHint => isArabic ? 'اكتب…' : 'Write…';
  static String get send => isArabic ? 'إرسال' : 'Send';
  static String get messageByteLimit =>
      isArabic ? 'الرسالة كلش طويلةو شوي اختصر' : 'Too long, trim it a little';
  static String get peerLeft =>
      isArabic ? 'صاحبك صار بعيد' : 'Your friend is out of range';
  static String get delivered => isArabic ? 'وصلت' : 'Delivered';
  static String get sending => isArabic ? 'ارسال...' : 'Sending…';
  static String get failed => isArabic ? 'ما وصلت' : 'Not delivered';
  static String get yesterday => isArabic ? 'امس' : 'Yesterday';
  static String get neighborhoodTopicHint => isArabic
      ? 'هذا موضوع الجوار، كل من حولك بيعرفه.'
      : 'This is the neighborhood thread, everyone around you will see it.';
  static String get dmTopicHint => isArabic
      ? 'هذا موضوع خاص, مشفر من طرف لطرف.'
      : 'This is a private thread, encrypted end to end.';

  // ---- QR.
  static String get myCard => isArabic ? 'رمزي' : 'My code';
  static String get myCardHint => isArabic
      ? 'خلي صاحبك يمسح الرمز حتى يضيفك. لا بيانات حساسة تنتقل.'
      : 'Let your friend scan this to add you. No sensitive data is transferred.';
  static String get scanFriend =>
      isArabic ? 'امسح رمز صاحبك' : "Scan a friend's code";
  static String get scanHint =>
      isArabic ? 'امسح رمز صديقك' : "Scan your friend's code";
  static String get scannedFriend =>
      isArabic ? 'تم حفض الصديق' : 'Friend saved';
  static String get invalidQr => isArabic ? 'الرمز غير صالح' : 'Invalid code';
  static String get copyMyCard => isArabic ? 'انسخ بطاقتي' : 'Copy my card';
  static String get pairingIdHint =>
      isArabic ? 'شنو تريد تسمي صاحبك؟' : 'What do you want to call them?';
  static String get cameraPermissionDenied => isArabic
      ? 'نحتاج إذن الكاميرا حتى نمسح الرمز.'
      : 'We need camera permission to scan codes.';

  // ---- settings.
  static String get settingsTitle => isArabic ? 'الإعدادات' : 'Settings';
  static String get myIdentity => isArabic ? 'هويتي' : 'My identity';
  static String get friendlyCode =>
      isArabic ? 'رمز الصداقة' : 'Friendship code';
  static String get securitySection =>
      isArabic ? 'السرية والأمان' : 'Privacy & security';
  static String get securityHint => isArabic
      ? 'المفاتيح محفوظة بأمان (Android Keystore / iOS Keychain) وتشفّر كل رسالة ATT قبل ما تطلع من الجوال.'
      : 'Keys live in secure hardware (Android Keystore / iOS Keychain); every message is encrypted before it leaves the phone.';
  static String get backup => isArabic ? 'نسخ احتياطي' : 'Backup';
  static String get backupExport =>
      isArabic ? 'صدّر الأرشيف' : 'Export archive';
  static String get backupImport =>
      isArabic ? 'استيراد الأرشيف' : 'Import archive';
  static String get eraseAll => isArabic ? 'امسح كل شيء' : 'Erase everything';
  static String get eraseConfirm => isArabic
      ? 'متأكد؟ كل الرسائل والهوية راح تُنمسح نهائياً.'
      : 'Are you sure? Every message and your identity will be wiped for good.';
  static String get quitRelaying => isArabic ? 'أوقف الترحيل' : 'Stop relaying';
  static String get relayMode => isArabic
      ? 'الترحيل (نقل رسائل الجوار)'
      : "Relay (carrying neighbors' messages)";
  static String get relayOn => isArabic ? 'فعّل' : 'On';
  static String get relayOff => isArabic ? 'أوقف' : 'Off';

  // ---- errors.
  static String get errorGeneric => isArabic
      ? 'صارت مشكلة, جرب مرة ثانية'
      : 'Something went wrong, try again';
  static String get errorBluetoothOff => isArabic
      ? 'بلوتوث مطفي, شغله اول شي بعدين جرب'
      : 'Bluetooth is off, turn it on first, then retry';
  static String get errorBluetoothUnsupported =>
      isArabic ? 'هذا الجهاز ما يدعم BLE' : 'This device does not support BLE';
  static String get errorPermissionDenied => isArabic
      ? 'ما نطيتنا الإذن للبلوتوث'
      : 'Bluetooth permission was not granted';
  static String get errorNoMessage => isArabic
      ? 'الرسالة فارغة, تريد ترسل امنياتك؟'
      : 'The message is empty, sending wishes?';

  static String get dangerZone => isArabic ? 'خطر' : 'Danger zone';
  static String get done => isArabic ? 'تم' : 'Done';
  static String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  static String get close => isArabic ? 'إغلاق' : 'Close';
}
