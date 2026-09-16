<div align="center">

<img src="assets/banner/banner.svg" alt="Spill the Tea, صب الجاي" width="100%" />

<br/>

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-14284F?style=for-the-badge)
![Encryption](https://img.shields.io/badge/encryption-AES--256--GCM-C8A852?style=for-the-badge)
![Network](https://img.shields.io/badge/network-Bluetooth%20LE%20mesh-2FB8AC?style=for-the-badge)

</div>

<br/>

## About

**Spill the Tea** is a privacy-first, offline messaging app for local communication without internet, servers, or central infrastructure. It lets people send messages to nearby devices over Bluetooth, forming a small peer-to-peer mesh network that carries messages between phones nearby. It's built for real-world situations where connectivity is limited, unreliable, or unavailable.

The experience is intentionally simple:

<table>
<tr>
<td align="center" width="25%">🪪<br/><b>Create your identity</b><br/><sub>Keys generated on-device</sub></td>
<td align="center" width="25%">📷<br/><b>Scan a QR code</b><br/><sub>Exchange public keys face to face</sub></td>
<td align="center" width="25%">📶<br/><b>Connect over Bluetooth</b><br/><sub>No SIM, no cloud, no account</sub></td>
<td align="center" width="25%">💬<br/><b>Start chatting</b><br/><sub>Messages hop through the mesh</sub></td>
</tr>
</table>

---

## Inspiration

This project is inspired by the spirit of **FireChat**, the early offline messaging app that showed people could communicate without mobile networks by using local wireless connections. FireChat proved that messaging could work without infrastructure, especially in crowded areas or emergency situations.

Spill the Tea carries that idea forward, reinterpreted for a more local-first, privacy-minded, and culturally grounded experience.

---

## How we differ from FireChat

FireChat was a breakthrough because it demonstrated that offline, Bluetooth-based communication was possible. Spill the Tea builds on that idea in a few important ways:

<table>
<tr>
<th align="left" width="22%">🔒 Privacy-first by design</th>
<td>Identities stay local, keys are generated on-device, messages are encrypted before they leave the phone, and no central server is required to route or store conversations.</td>
</tr>
<tr>
<th align="left">🛡️ Stronger local security</th>
<td>Public-key pairing via QR, encrypted session setup, end-to-end message protection (AES-256-GCM), no plaintext message storage in the main app database.</td>
</tr>
<tr>
<th align="left">🕸️ Mesh-aware communication</th>
<td>Built around neighborhood broadcasting and relay behavior; nearby devices help carry messages through the local mesh instead of relying on a single direct connection.</td>
</tr>
<tr>
<th align="left">🗺️ Social + neighborhood view</th>
<td>A local neighborhood/radar concept, not just one-to-one messaging. Users can see nearby peers and understand local network presence.</td>
</tr>
<tr>
<th align="left">🕌 Arabic-first brand and UX</th>
<td>Built around a bilingual Arabic/English experience, with a visual language that's local, warm, and culturally rooted rather than a generic tech interface.</td>
</tr>
<tr>
<th align="left">🏜️ Purpose-built for resilience</th>
<td>Not a clone of an offline chat idea. A practical local communication tool for situations where internet access is unavailable, censored, or simply nonexistent.</td>
</tr>
</table>

---

## Core idea

Spill the Tea is built around a simple principle: **communication should still work when the internet does not.**

Instead of depending on cloud infrastructure, it uses:

- Bluetooth Low Energy
- Local peer discovery
- QR-based identity exchange
- Encrypted direct messages
- Neighborhood-wide broadcast threads

This makes it useful for:

- Festivals or gatherings
- Remote areas
- Outages or network disruptions
- Privacy-sensitive offline communication
- Communities that want communication without centralized platforms

---

## Product vision

Spill the Tea is not trying to replace global messaging platforms. Instead, it offers a different mode of communication: a local, private, resilient way to talk when the internet is down, the network is unreliable, or users simply want communication without a central authority.

It is a small but meaningful step toward more resilient, human-centered messaging.

---

## Tech stack

| Layer | Choice |
|---|---|
| Framework | Flutter / Dart |
| Connectivity | Bluetooth Low Energy (BLE) mesh |
| Encryption | AES-256-GCM, end-to-end |
| Key storage | Android Keystore / iOS Keychain |
| Pairing | QR code exchange of public keys |
| Platforms | iOS, Android |

---

## Brand palette

<table>
<tr><td><img src="https://img.shields.io/badge/-%20-0A1B3D?style=for-the-badge"/></td><td><b>Deep navy / lapis</b></td><td><code>#0A1B3D</code></td><td>Dark background</td></tr>
<tr><td><img src="https://img.shields.io/badge/-%20-C8A852?style=for-the-badge"/></td><td><b>Antique gold</b></td><td><code>#C8A852</code></td><td>Primary accent / highlights</td></tr>
<tr><td><img src="https://img.shields.io/badge/-%20-B08D57?style=for-the-badge"/></td><td><b>Brass</b></td><td><code>#B08D57</code></td><td>Supportive warm metallic tone</td></tr>
<tr><td><img src="https://img.shields.io/badge/-%20-2FB8AC?style=for-the-badge"/></td><td><b>Turquoise</b></td><td><code>#2FB8AC</code></td><td>Active / success / info accent</td></tr>
<tr><td><img src="https://img.shields.io/badge/-%20-9E2B3E?style=for-the-badge"/></td><td><b>Pomegranate</b></td><td><code>#9E2B3E</code></td><td>Destructive / alert red</td></tr>
<tr><td><img src="https://img.shields.io/badge/-%20-F5F1E3?style=for-the-badge"/></td><td><b>Ivory</b></td><td><code>#F5F1E3</code></td><td>Text / light foreground</td></tr>
</table>

---

<div align="center">
<sub>🍵 صب الجاي, a small, meaningful step toward more resilient, human-centered messaging.</sub>
</div>
