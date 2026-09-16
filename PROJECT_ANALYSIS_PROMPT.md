# Project Analysis and Improvement Prompt

## Project Summary

`Spill the Tea` (`صب الجاي`) is an Arabic-first Flutter application for offline, peer-to-peer messaging over Bluetooth Low Energy. It targets Android and iOS and does not depend on servers, internet access, mobile data, or SIM cards.

The app currently provides:

- BLE discovery and mesh links using central and peripheral roles.
- A neighborhood broadcast conversation that can relay messages across nearby devices.
- Direct peer-to-peer conversations after QR pairing.
- QR identity cards containing public keys only.
- Ed25519-signed identity hello packets.
- X25519 key agreement and AES-256-GCM message sealing.
- Encrypted Hive-backed local storage protected by a per-install key in Android Keystore or iOS Keychain.
- Onboarding, nearby-peer radar, chat list, chat view, QR display/scanning, settings, relay controls, backup, and destructive erase controls.
- Arabic-first RTL copy with English support, custom fonts, a lapis, gold, turquoise, and pomegranate visual palette, and an existing animated radar/orbit visualization.

## Current Repository State

### Top-level project

- `pubspec.yaml`: Flutter dependencies, fonts, BLE, cryptography, secure storage, Hive, QR, and scanner packages.
- `analysis_options.yaml` and `devtools_options.yaml`: Dart and Flutter tooling configuration.
- `android/` and `ios/`: native platform projects, permissions, BLE integration, and application configuration.
- `assets/fonts/`: bundled Arabic-oriented font files and license texts.
- `lib/`: application source.
- `test/`: unit and widget tests.
- `build/`: generated Flutter/build output; do not manually edit or analyze as product source unless a build issue specifically requires it.
- `README.md`: product description, security model, setup instructions, layout, and known v1 limits.

### Application source

- `lib/main.dart`: Flutter startup and system UI styling.
- `lib/app.dart`: providers, theme, localization, ambient background, and onboarding/home gate.
- `lib/core/crypto/tea_crypto.dart`: Ed25519 signing, X25519 operations, HKDF derivation, AES-256-GCM sealing, and newer forward-secret DM primitives.
- `lib/core/crypto/dm_ratchet.dart`: bounded symmetric-chain walking and skipped-message-key handling for ratcheted DMs.
- `lib/core/utils/`: sanitization, safe logging, time formatting, QR payload parsing, and related utilities.
- `lib/models/peer.dart`: verified peer identity plus newer public pre-key metadata.
- `lib/models/stored_message.dart`: local message model and protocol limits.
- `lib/storage/secure_identity_store.dart`: identity and database-key persistence through platform secure storage.
- `lib/storage/local_vault.dart`: encrypted local Hive vault.
- `lib/storage/backup_service.dart`: encrypted offline backup and restore.
- `lib/mesh/ble_constants.dart`: BLE UUIDs and bounded frame settings.
- `lib/mesh/fragmenter.dart`: framed packet fragmentation and reassembly.
- `lib/mesh/message_envelope.dart`: wire envelope parsing/building, legacy message kinds, v2 direct-message headers, and pre-key announcements.
- `lib/mesh/protocol.dart`: signed identity hello packets and protocol utilities.
- `lib/mesh/mesh_service.dart`: BLE lifecycle, peer registration, send/receive/relay behavior, broadcast handling, and DM integration.
- `lib/mesh/session_store.dart`: encrypted rotating pre-key and per-peer ratchet state persistence. This is currently uncommitted work and must be validated before being described as complete.
- `lib/services/`: bootstrap and messaging state coordination.
- `lib/screens/`: onboarding, home shell, radar, chat list, chat view, QR screens, and settings.
- `lib/theme/`: palette and Material theme.
- `lib/widgets/`: tea logo, avatars, mesh orbit painter, and decorative UI primitives.
- `lib/l10n/app_strings.dart`: Arabic-first user-facing strings.

### Tests and current status

- `test/core_test.dart`: cryptographic round trips, signatures, hello packets, message envelopes, sanitization, and QR payload tests.
- `test/widget_test.dart`: basic app boot/splash coverage.
- The working tree contains uncommitted changes in cryptography, mesh, peer modeling, local storage, and tests, plus new DM ratchet/session-store files. Preserve those changes and do not reset or overwrite them.
- The current codebase should be treated as an active v1/v2 transition: legacy direct-message paths and newer ratcheted DM paths may coexist. Confirm actual call paths and run tests before making security claims.

## Engineering Task

Analyze the project comprehensively before editing. Inspect all product source folders and relevant configuration, but ignore generated build output unless it is directly relevant to a failure. Explain the current architecture, identify incomplete or risky behavior, and propose the smallest coherent sequence of improvements.

Then improve the product only after understanding the existing code and preserving its architecture.

## Non-negotiable constraints

1. Do not overwrite, delete, reset, or reformat code written by the project owner.
2. Keep unrelated worktree changes intact.
3. Preserve public APIs and existing behavior unless a change is required for a verified bug or explicitly approved feature.
4. Do not claim end-to-end privacy, forward secrecy, or map accuracy unless the implementation and tests demonstrate it.
5. Keep security changes separate from visual changes and test each slice independently.
6. Use Flutter/Dart idioms. The supplied React/TypeScript logo snippet is design source, not code to paste literally into a Flutter file.
7. Prefer existing dependencies and project patterns. Do not add a package without explaining why it is needed.
8. Add focused tests for changed behavior and run formatting, analysis, and tests after edits.

## UI direction

Make the interface feel authored, warm, local, and useful rather than generic or AI-generated. Preserve the Arabic-first RTL identity, the lapis-and-antique-gold world, the existing custom fonts, and the tea/lantern concept. Avoid generic dashboard cards, excessive rounded containers, default Material-looking layouts, decorative clutter, repetitive gradients, and unexplained status text.

Improve hierarchy, spacing, typography, empty states, loading states, error states, touch targets, and small-screen behavior. The interface should make the nearby network understandable at a glance and should distinguish direct conversations from neighborhood broadcasts.

## Logo requirement

Use the following animated cup/chat-bubble/steam mark as the visual source for the app logo:

```tsx
export function Logo({ className = "w-10 h-10", steam = true }: LogoProps) {
  return (
    <svg viewBox="0 0 64 64" className={className} aria-hidden="true">
      <g fill="none" stroke="currentColor" strokeWidth="3"
         strokeLinecap="round" strokeLinejoin="round">
        <path d="M10 24h32a4 4 0 0 1 4 4v13a9 9 0 0 1-9 9H23l-9 8v-8h-2a4 4 0 0 1-4-4V28a4 4 0 0 1 2-4Z" />
        <path d="M46 30c6.5.6 8.5 3.2 8.5 6.4S52.5 43.6 46 44" />
        <path d="M14 32h28" strokeWidth="2" opacity=".55" />
      </g>
      {steam && (
        <g stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" fill="none">
          {[0, 1, 2].map((i) => (
            <path key={i}
              d={`M${20 + i * 8} 17c-3.2-2.6 2.6-4.4-.6-7.4`}
              style={{
                transformOrigin: `${20 + i * 8}px 17px`,
                animation: `steam-rise 2.6s ease-out ${i * 0.55}s infinite`,
              }}
            />
          ))}
        </g>
      )}
    </svg>
  );
}
```

Adapt the geometry faithfully to Flutter using the smallest suitable existing approach, such as a custom painter or an existing vector asset strategy. Keep the mark accessible and animate steam only where animation is supported and useful. Do not paste React syntax into Dart.

## Wordmark requirement

Create or refine the wordmark using the cup mark, the Arabic name, and the English tagline. The requested change is specifically to adjust the spacing between the Arabic and English text so the relationship feels intentional and readable in RTL and LTR contexts. Do not change the owner’s existing code until the relevant widget and typography have been inspected.

## Radar/map requirement

Inspect the existing radar/orbit painter and the real BLE data it receives before calling it a map. Improve the visualization so it communicates nearby peers, connection state, relay availability, and message reach without inventing GPS locations or implying geographic precision. Keep it performant, legible, accessible, and stable with zero peers, one peer, many peers, Bluetooth disabled, and rapidly changing peer lists.

## Required final report

After implementation, report:

- What was discovered about the current project.
- What was changed and why.
- Which owner-authored files were left untouched.
- Security behavior that is actually implemented versus still pending.
- Tests, analysis, formatting, and device checks that were run.
- Any remaining risks, especially around ratchet interoperability, key rotation, relay privacy, metadata leakage, backups, and BLE platform behavior.
