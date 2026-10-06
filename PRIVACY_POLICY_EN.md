# ALK Privacy Policy

**Last updated:** September 29, 2026
**App name:** ALK — Health Companion
**Package ID:** `com.alk.health`

> This policy matches the actual behavior of the app:
> local-only storage, no accounts, no tracking, no ads.

## 1) Quick summary

- Your health data stays on your phone only.
- No user accounts and no servers collecting your data.
- No ads, no tracking, no data selling — ever.
- Only you send your report to your doctor, when you choose to.
- You can delete all your data from inside the app at any time.

## 2) Data and where it is stored

- Patient profile: name, ID number, condition, doctor notes,
  review date, doctor phone and email.
- Medications: names, times, doses, taken and missed history.
- Vitals: pressure, sugar, pulse, oxygen (manual or device).
- Meals: breakfast, lunch, dinner, snacks with analysis.
- Journals, mood, emergency contacts, ambulance number.
- Medication photos and reports in the app private folders.

All of the above is stored in `alk-data.json`, encrypted with
AES-256-GCM, inside the app private folder on your device. The
encryption key is kept in the device secure vault (Android Keystore /
iOS Keychain). It never leaves your device unless you export a backup
or send a report yourself. Cloud backup, device transfer, and
`adb backup` are explicitly disabled for this app.

## 3) Permissions and why we ask for them

- Notifications and exact alarms: dose reminders and level 1/2
  food alerts on time, even when the app is closed.
- Bluetooth: discover meters and receive their readings.
- Health Connect: import your watch readings.
- Microphone: the big mic button in the voice assistant only.
- Camera and gallery: medication photo and report attachment only.
- Biometrics: optional app lock.
- Phone calls: emergency buttons only when you tap them.
- Internet: one-time UI translation, and DeepSeek
  chat only with your own key. Daily tasks work offline.

## 4) External services (only when you ask)

- DeepSeek: works only with your own key; when you tap the AI
  button, only your question text is sent to
  `https://api.deepseek.com/chat/completions`.
- UI translation: Arabic is the source; on non-Arabic phones the
  general UI strings are translated once and stored on device.

## 5) What you send yourself

- Doctor report: never automatic — you tap WhatsApp, email,
  or share, then confirm sending yourself.
- Backup `alk-backup-*.json`: you export and keep it yourself.
- Feedback: opens the developer WhatsApp with your message only.

## 6) Children

- The app is designed for seniors and caregivers, not for children.
- We do not knowingly collect children data.

## 7) Retention and deletion

- Default 30 days for changing data, adjustable up to forever.
- Clear-all in Settings deletes the local file permanently.
- Uninstalling the app removes its data per Android rules.

## 8) Security

- Data is encrypted on the device (AES-256-GCM); its key is stored in
  the device secure vault (Keystore / Keychain), beyond the reach of
  other apps.
- Cloud backup, device transfer, and `adb backup` are disabled for
  this app, so your data is not copied off the device automatically.
- Optional biometric, face, or device-code lock. The app relocks
  automatically when you leave it or turn off the screen, and every
  screen — including ones opened from notifications or shortcuts —
  stays behind the lock.
- Screenshots and the recent-apps preview are blocked for the app.
- A DeepSeek key, if you enter one, is stored in the device secure
  vault and displayed in hidden form.
- Detailed medical content does not appear on the lock screen in
  notifications.
- Release builds are signed with a private key that is never shared,
  so app updates cannot come from another party.
- No network transfer except section 4 above.

## 9) Your rights

- Access: all your data is visible inside the app screens.
- Correction: edit any record from its screen.
- Deletion: delete any record or wipe everything in Settings.
- Your JSON backup is your full copy — there is no server copy.

## 10) Changes and contact

- Material changes update the date at the top of this file.
- Contact: in-app Settings, feedback button (WhatsApp).
