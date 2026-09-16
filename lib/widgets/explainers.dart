import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

/// Reusable explainer widgets, shared by Settings: how the app works and how
/// Bluetooth messaging works. Both read the live language, so they re-render
/// when the locale flips.

/// Three numbered steps — identity, pair, talk — as carved stone cards.
class HowItWorksSection extends StatelessWidget {
  const HowItWorksSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _sectionTitle(context, AppStrings.howTitle, Icons.auto_stories_outlined),
        const SizedBox(height: 12),
        _StepCard(
          number: 1,
          icon: Icons.badge_outlined,
          title: AppStrings.howStep1Title,
          body: AppStrings.howStep1Body,
        ),
        const SizedBox(height: 10),
        _StepCard(
          number: 2,
          icon: Icons.qr_code_scanner,
          title: AppStrings.howStep2Title,
          body: AppStrings.howStep2Body,
        ),
        const SizedBox(height: 10),
        _StepCard(
          number: 3,
          icon: Icons.hub_outlined,
          title: AppStrings.howStep3Title,
          body: AppStrings.howStep3Body,
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _stoneDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Gold step numeral inside a hairline ring.
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppPalette.gold.withValues(alpha: 0.85),
                width: 1.1,
              ),
              color: AppPalette.lapisHigh.withValues(alpha: 0.6),
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontFamily: 'ReemKufi',
                fontSize: 19,
                color: AppPalette.goldLight,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(icon, size: 17, color: AppPalette.gold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppPalette.goldLight,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How Bluetooth messaging actually works — four plain truths, no magic.
class BluetoothCard extends StatelessWidget {
  const BluetoothCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _stoneDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bluetooth_audio, size: 18, color: AppPalette.gold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AppStrings.btTitle,
                  style: const TextStyle(
                    color: AppPalette.goldLight,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List<Widget>.generate(AppStrings.btPoints.length, (int i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // The same tiny gold diamond the rules use — a bullet that
                  // belongs to the brand.
                  Transform.rotate(
                    angle: 0.7854,
                    child: Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 7),
                      color: AppPalette.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppStrings.btPoints[i],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- shared

Widget _sectionTitle(BuildContext context, String title, IconData icon) {
  return Row(
    children: <Widget>[
      Icon(icon, size: 16, color: AppPalette.gold),
      const SizedBox(width: 6),
      Text(
        title,
        style: const TextStyle(
          color: AppPalette.goldLight,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Divider(color: AppPalette.dividerGold, thickness: 0.6),
      ),
    ],
  );
}

Decoration _stoneDecoration() {
  return BoxDecoration(
    color: AppPalette.lapisMid.withValues(alpha: 0.55),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppPalette.dividerGold, width: 0.8),
  );
}