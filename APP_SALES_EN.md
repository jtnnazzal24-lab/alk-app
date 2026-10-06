# ALK — Your Health Companion | Sales / Deal Sheet
**Version:** 1.0.1+2 | **Platform:** Flutter (Android / iOS / Web / Windows / Linux) | **Languages:** Arabic & English

> A complete, ready-to-sell health app designed especially for elderly users:
> medications + vitals + nutrition + mood journal + slow voice assistant +
> unique food×morning-med analysis + optional AI. Works offline and keeps all
> data on the device only (full privacy).

## What it is & key features
- **Audience:** seniors, families and caregivers — simple no-typing UI, slow clear voice.
- **Medications:** exact local alarms + 15-min snooze + confirm dose + daily adherence.
- **Vitals:** BP/sugar/pulse + trend charts + Health Connect sync + read-aloud.
- **Unique feature — food × morning med:** per meal it shows allowed portion,
healthy alternative and medicine-timing advice (conflicting breakfast = high risk).
- **Journal × Wellbeing:** logging your mood instantly suggests matching exercises + music.
- **Voice assistant:** big-mic button understands commands (log sugar, ate an apple,
open medications, call emergency...) and replies slowly.
- **Optional AI:** DeepSeek with the user's own key only; fully local without it.
- **Language:** Arabic (RTL) and English only, auto-applied from the device and saved.
- **Privacy:** local storage + biometric lock + backup/restore + retention auto-delete.

## 4) Screens (14 total)
## 4) Screens (14 total)
| Screen | Purpose |
|---|---|
| Home | time greeting + adherence rate + today's meds + big-mic button |
| Medications | list + add + confirm dose + speak each medication |
| Vitals | BP/sugar/pulse + charts + watch sync + read-aloud |
| Nutrition | log meals + morning-med analysis (portion/alternative/timing) per meal |
| Journal | mood + note + instant wellbeing suggestion per mood |
| Wellbeing | breathing + mood-based music + tips + AI button |
| Reports | adherence & vitals summary (PDF/share) |
| Chat | DeepSeek AI or local offline answers |
| Voice Assistant | big-mic button understands spoken commands & replies slowly |
| Patient Profile | health identity & medications |
| Emergency | contacts + ambulance number + fast dial |
| Lock | fingerprint/face unlock |
| Settings | language (ar/en) + voice speed + reminders + backups |
| More | gateway to all features |

## 5) Technical stack (for buyer/developer)
- Flutter + Provider: one codebase for Android, iOS, Web and desktop.
- Storage: `alk-data.json` + SharedPreferences using the same `sandy-health-local-v1` schema.
- Notifications: `flutter_local_notifications` exact alarms with system channels.
- Voice: `flutter_tts` at 0.52 rate for seniors + `speech_to_text` for commands.
- AI: DeepSeek over HTTP using only the user's key (optional).
- Health: `health` (Health Connect); reports: `share_plus`/`file_picker`.
- Tests: 61 passing (`flutter test`) + clean `flutter analyze`.
- Run: `flutter pub get` then `flutter run`; build: `flutter build apk --release`.

## 6) Why would someone buy it? (business value)
- A large underserved audience: seniors and their families — slow voice, no typing.
- Unique feature: food × morning-medication analysis (portion + alternative)
rarely found in other apps.
- Privacy: data stays only on the device — more trust and zero cloud cost.
- Works offline + native Arabic RTL + full English.
- Easily expandable: clinics, pharmacies, health insurance
(monitoring dashboards, family edition).