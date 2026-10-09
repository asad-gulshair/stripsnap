# StripSnap

Android app that reads **any brand** of pool / hot-tub test strip from one photo: the strip is
compared with the bottle's own color chart in the same photo, so lighting errors cancel out.
Then it tells you what to add for your pool size. Results are estimates: always follow product
labels and retest.

## Get the APK / AAB
Every push to `main` builds the app on GitHub: **Actions → latest "Build APK + AAB" run → Artifacts**
- `StripSnap-apk`: zip with `app-release.apk`. Copy to your phone and install (allow "install unknown apps" once).
- `StripSnap-aab`: zip with `app-release.aab`. This is the file you upload to Google Play.

Without the signing secrets the builds use the debug key (fine for your own phone, not for Play).
Signing secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) go in
**Settings → Secrets and variables → Actions**. The keystore itself is never committed.

## Project
- `lib/engine/reader.dart`: color reading (Dart port of the tested Python engine)
- `lib/engine/dosing.dart`: what to add (rule-of-thumb amounts, shown as estimates)
- `lib/engine/profiles.dart`: strip layouts (test order + printed values)
- `lib/main.dart`: screens (home/history, my water, line up frames, results)
- `test/engine_test.dart`: engine + dosing tests (run in CI)
- `field_check/`: "phone-like photo" check (glare, shadow, tilt, random photos...). Run
  `python field_check/make_cases.py` then `flutter test field_check/field_check_test.dart`.
- `tool/make_icons.py`: draws the launcher icon and Play Store graphics
- `docs/privacy-policy.html`: privacy policy (must be hosted at a public URL for Play)

## Status
v0.1, tested on computer-made photos only. Known weak spot: a tilted strip can still be misread.
Real strip photos are needed before Play Store release.