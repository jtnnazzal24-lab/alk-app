# ALK App Documentation — Your Health Companion
**Version:** 1.0.1+2 | **Platform:** Flutter (Android / iOS / Web / Windows / Linux) | **Languages:** Arabic & English

## 1) What is the app?
A bilingual (Arabic-English) health companion built specially **for elderly users**:
it helps them track medications, vital signs (BP/sugar/pulse/SpO2), nutrition, and mood —
with a slow, clear voice and **no typing needed** (big-mic voice assistant).
It connects to **certified measuring devices** (BP monitors, glucose meters, pulse
oximeters) and records their readings **automatically**, with the device error
margin taken into account.
It works **fully offline** for daily tasks and keeps **all data on the user's device**
(full privacy, no cloud account required).

## 2) How does it work? (user journey)
1. On first launch the app detects the carrier's device language (Arabic/English)
and saves it permanently — no re-translation on every start.
2. The user registers medications (name + time + category: diabetes/BP/heart/general)
and receives exact local alarms with a slow spoken reminder.
3. Each dose is confirmed with one tap; the app computes the daily adherence rate.
4. Vitals are logged manually, synced from smartwatches (Health Connect), or pushed
**live from paired Bluetooth meters** — no manual entry needed; every automatic
reading is validated against physiologically plausible ranges and the known device
error margin before it is stored.
5. Meals are logged (breakfast/lunch/dinner); the app analyzes their effect on the
**morning medication** with a portion limit and a healthy alternative per item.
6. Mood is logged in "Journal"; the app instantly suggests matching exercises + music.
7. The health report can be sent **directly to the treating doctor** via WhatsApp,
email, or any other share channel.
8. Whenever local knowledge is insufficient, the user can ask the AI (DeepSeek)
after adding their own API key.

## 3) Full feature list
### Medications & reminders
- Add medications (name/dose/form/multiple times/daily-to-weekly repeat/category).
- Exact local alarms + 15-min snooze + one-tap confirm, with 3 rotating message
variants per language, all spoken slowly.
- **Reliable background delivery**: the app verifies notification permission,
falls back to inexact alarms when exact-alarm permission is missing, and lets the
user request a **battery-optimization exemption** (Settings → "Background
notifications" status card) so reminders keep firing while the app is closed —
critical on Xiaomi/Huawei/Samsung power-saving modes.
### Vitals & connected measuring devices
- BP/sugar/pulse/**SpO2** with trend charts + slow read-aloud.
- **Bluetooth LE meters** (standard Bluetooth SIG GATT profiles): blood-pressure
monitors (0x1810), glucose meters (0x1808), heart-rate belts (0x180D) and pulse
oximeters (0x1822) are discovered, paired from the Vitals screen ("Connected
measuring devices" card) and push every measurement **live** — the patient never
enters a number manually. The app auto-reconnects to paired meters on every launch.
- **Health Connect sync** (any synced wearable) runs automatically every 10 minutes
and on app start, plus a manual "Sync from my device" button.
- **Measurement-error policy**: every automatic reading is checked against
physiologically plausible ranges (impossible values are dropped) and against the
normalized device error margin (BP ±5 mmHg, glucose ±15% ISO 15197, pulse ±3 bpm,
SpO2 ±2%); suspicious readings are stored flagged "needs re-check" with an
explanatory note (long-press any reading).
### Reports → treating doctor
- Reports screen shows adherence, latest readings and missed doses, and can be
sent **directly to the treating doctor** via **WhatsApp**, **email**, or the
system **share sheet** (any other app).
- Doctor contact (international WhatsApp number + email) is stored in the patient
profile and can be edited inline when sending.
### Food × morning-medication analysis (unique feature)
- Auto-detects morning meds (dose before 12:00) and links their category to food effects.
- Per meal: risk badge (high/medium/low) + summary + per item: portion + alternative + timing.
- Conflicting breakfast = high risk (closest to the dose).
### Elderly-first voice assistant
- Big-mic button: speak and it understands (log sugar 140, ate an apple,
open medications, call ambulance...).
- All replies in slow voice (0.52) with pauses + "Voice speed" setting with preview.
- "Read to me" speaker buttons on every screen.
### Journal + Wellbeing (linked)
- Log mood (relaxed/calm/tired/sad...); immediately get matching exercises + music.
- Wellbeing screen: animated breathing exercise + mood-based music + tips + AI button.
### Optional AI (DeepSeek)
- User-provided API key, stored on-device; without it the app is fully local.
- "Not enough info? Ask the AI" button in Journal and Wellbeing.
### Language (Arabic/English only)
- Language list: Arabic and English only. Device language applied once and saved.
- No repeated translation, no internet needed for the UI.
### Privacy & safety
- Local storage (JSON file + SharedPreferences), biometric lock, backup/restore,
auto-delete by retention window, emergency contacts + ambulance number,
quiet mode and travel mode.
## 4) Screens (14 total)
| Screen | Purpose |
|---|---|
| Home | time greeting + adherence rate + today's meds + big-mic button |
| Medications | list + add + confirm dose + speak each medication |
| Vitals | BP/sugar/pulse/SpO2 + charts + watch sync + paired Bluetooth meters + read-aloud |
| Nutrition | log meals + morning-med analysis (portion/alternative/timing) per meal |
| Journal | mood + note + instant wellbeing suggestion per mood |
| Wellbeing | breathing + mood-based music + tips + AI button |
| Reports | adherence & vitals summary + send to treating doctor (WhatsApp/email/share) |
| Chat | DeepSeek AI or local offline answers |
| Voice Assistant | big-mic button understands spoken commands & replies slowly |
| Patient Profile | health identity + medications + treating-doctor contact (WhatsApp/email) |
| Emergency | contacts + ambulance number + fast dial |
| Lock | fingerprint/face unlock |
| Settings | language (ar/en) + voice speed + background-notification status + backups |
| More | gateway to all features |

## 5) Technical stack
- Flutter + Provider: one codebase for Android, iOS, Web and desktop.
- Storage: `alk-data.json` + SharedPreferences using the same `sandy-health-local-v1` schema.
- Notifications: `flutter_local_notifications` alarms with exact→inexact fallback,
  runtime `POST_NOTIFICATIONS` request and battery-optimization exemption flow.
- Devices: `flutter_blue_plus` for Bluetooth LE meters (standard SIG GATT profiles,
  IEEE-11073 SFLOAT decoding) + `health` (Health Connect) with 10-minute polling
  (`DeviceSyncService`) and a shared measurement-quality policy (`VitalQualityPolicy`).
- Voice: `flutter_tts` at 0.52 rate + `speech_to_text` for commands.
- AI: DeepSeek over HTTP using only the user's key (optional).
- Doctor delivery: `url_launcher` (WhatsApp `wa.me` + `mailto`) and `share_plus`.
- Tests: 108 passing (`flutter test`) + clean `flutter analyze`.

## 6) Android permissions & requirements
| Permission | Why |
|---|---|
| `POST_NOTIFICATIONS` | dose reminders (runtime dialog on Android 13+) |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | exact dose alarms (with inexact fallback) |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | keeps reminders alive in the background |
| `RECEIVE_BOOT_COMPLETED` | re-arms reminders after reboot |
| `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (+ legacy Bluetooth & location ≤ Android 11) | discovering and pairing certified meters |
| `HEALTH_*` (Health Connect) | reading vitals synced by wearables |

> **Note:** after installing a new build, open Settings → "Background
> notifications" inside the app to grant the battery-optimization exemption —
> this is what keeps dose reminders and device syncing alive while the app is
> closed. Only meters implementing the standard Bluetooth SIG profiles appear
> in the scan; proprietary-protocol meters still deliver their data through
> Health Connect (smartwatches) automatically.
