import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/locale_controller.dart';
import '../../services/app_bootstrap.dart';
import '../../theme/app_palette.dart';
import '../../widgets/avatars.dart';
import '../../widgets/tea_wordmark.dart';

/// First launch: the brand lockup, an intro, two honest explainers (how the
/// app works, how Bluetooth messaging works), a language toggle, then one
/// name field and a gold button. Nothing else.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy) {
      return;
    }
    final String value = _name.text.trim();
    if (value.isEmpty) {
      _showToast(AppStrings.chooseDisplayName);
      return;
    }
    setState(() => _busy = true);
    final AppBootstrap bootstrap = context.read<AppBootstrap>();
    final bool ok = await bootstrap.createIdentity(value);
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() => _busy = false);
      _showToast(AppStrings.errorGeneric);
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the locale so the toggle re-renders the whole intro in place.
    context.watch<LocaleController>();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 64),
              // Cup mark + Arabic name + Latin line as one lockup.
              const TeaWordmark(markSize: 128),
              const SizedBox(height: 26),
              const _LanguageToggle(),
              const SizedBox(height: 56),
              const GoldRuleDivider(),
              const SizedBox(height: 26),
              // The one thing we ask for.
              TextField(
                controller: _name,
                enabled: !_busy,
                textAlign: TextAlign.center,
                maxLength: 48,
                style: const TextStyle(color: AppPalette.ivory, fontSize: 17),
                decoration: InputDecoration(
                  hintText: AppStrings.nameHint,
                  counterText: '',
                ),
                onSubmitted: (_) => _continue(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _continue,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppPalette.ground,
                          ),
                        )
                      : const Icon(Icons.local_cafe_outlined, size: 20),
                  label: Text(AppStrings.startBrewing),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- language

/// The AR ⇄ EN switch: a carved-stone pill with two chambers, the active one
/// filled with gold leaf.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();

  @override
  Widget build(BuildContext context) {
    final LocaleController locale = context.watch<LocaleController>();
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppPalette.lapisMid.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppPalette.dividerGold, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _chamber(
            context,
            label: AppStrings.langAr,
            selected: locale.lang == AppLang.ar,
            onTap: () => locale.setLang(AppLang.ar),
          ),
          _chamber(
            context,
            label: AppStrings.langEn,
            selected: locale.lang == AppLang.en,
            onTap: () => locale.setLang(AppLang.en),
          ),
        ],
      ),
    );
  }

  Widget _chamber(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppPalette.gold : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Parastoo',
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppPalette.ground : AppPalette.ivoryDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// Route-safe clipboard copy helper (kept out of main activity code).
Future<void> copyToClipboard(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.done)),
    );
  }
}
