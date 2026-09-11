import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../services/app_bootstrap.dart';
import '../../theme/app_palette.dart';
import '../../widgets/avatars.dart';
import '../../widgets/tea_logo.dart';

/// First launch: choose how people will call you. One field, gold button.
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
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 24),
              const TeaLogo(size: 132),
              const SizedBox(height: 22),
              const Text(
                AppStrings.proverb,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'ArefRuqaa',
                  fontSize: 27,
                  color: AppPalette.goldLight,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.tagline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              const GoldRuleDivider(),
              const SizedBox(height: 28),
              Text(
                AppStrings.onboardingIntro,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _name,
                enabled: !_busy,
                textAlign: TextAlign.center,
                maxLength: 48,
                style: const TextStyle(color: AppPalette.ivory, fontSize: 17),
                decoration: const InputDecoration(
                  hintText: AppStrings.nameHint,
                  counterText: '',
                ),
                onSubmitted: (_) => _continue(),
              ),
              const SizedBox(height: 28),
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
                  label: const Text(AppStrings.startBrewing),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'iOS/Android · يعمل بدون إنترنت بالكامل',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
            ],
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
      const SnackBar(content: Text(AppStrings.done)),
    );
  }
}