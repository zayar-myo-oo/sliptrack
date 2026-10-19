# SlipTrack

A Flutter personal finance journal that imports bank e-slip images using authorized photo access and on-device OCR. No bank login, bank APIs, SMS access, notification listener, accessibility monitoring, or cloud OCR.

This is an implemented development app, with real native photo/OCR bridges and encrypted persistence. It is not a certified bank payment verifier or a production-ready store release. See [platform limitations](docs/PLATFORMS.md), [security](docs/SECURITY.md), and [validation](docs/VALIDATION.md).

## Current development snapshot

The latest manual-income, savings, companion and approximate currency conversion changes are still being integrated and have not passed a fresh full validation run. The companion UI and budget threshold logic are present; native budget-notification channel handlers still need implementation. Existing APKs and earlier test results do not validate these latest changes. iOS has not been compiled or tested on a device; it requires macOS/Xcode and signing configuration for both app targets. This repository is a work-in-progress source snapshot, not an install-ready iOS release.

## Run

Validated development SDK: Flutter **3.47.7**, Dart **3.13.5**. Dependencies are resolved in `pubspec.lock`. Android requires JDK 17, Android SDK platform/build tools 36 and NDK 28.2.13676358. iOS requires macOS, a compatible Xcode and iOS 15+.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

On this workspace, Flutter lives under `.tooling/flutter`. Windows projects whose SDK path contains spaces can encounter a Flutter native-assets quoting error. Run:

```powershell
.\scripts\check.ps1
# Or point at another installed SDK:
.\scripts\check.ps1 -FlutterRoot 'C:\flutter'
```

The check script invokes the same Flutter analyzer/test commands through the SDK's short Windows executable path. If 8.3 paths are disabled, use a Flutter SDK location without spaces.

Android:

```sh
flutter build apk --debug
```

For this Windows workspace, `.\scripts\build-android.ps1` also supplies the local SDK, JDK 17, short Flutter path and short temporary directory needed by the native toolchain. Release signing must be configured with a private keystore before distribution.

On macOS:

```sh
flutter build ios --simulator --debug --no-codesign
open ios/Runner.xcworkspace
```

For physical iOS devices, configure the Runner and SlipTrackShare targets with your development team, matching App Group and shared Keychain entitlements. Default identifiers are `app.sliptrack.sliptrack`, `app.sliptrack.sliptrack.share`, `group.app.sliptrack.sliptrack`, and `$(AppIdentifierPrefix)app.sliptrack.shared`. Change them consistently in both targets and their plists/entitlements. The extension is connected as a Runner dependency and embedded app extension. Align app/extension version and build numbers before releasing.

## Private phone use first

The current goal is private use on your own phone; public launch is optional later. The signed Android release APK is `build/app/outputs/flutter-apk/app-release.apk`. This build does not need a store listing and its merged release manifest excludes Internet permission. Real-device OCR still needs testing on your phone.

Private release signing material is stored locally in ignored `android/private-signing/sliptrack-private.jks` and `android/key.properties`. Keep a secure backup of both for future updates; neither file is committed or included in the app's financial-data export. The release build script reads them locally and never prints their passwords.

Main shows exactly the selected calendar month: income, expenses, net flow, recent receipts and review counts all use the same month. Previous/next controls and a date picker change the month. Transactions and Analytics provide the combined history across months, with THB and MMK still separated. Receipts without a transaction date remain in the review/history screens until a date is supplied.
## First import

1. Open SlipTrack and choose Get started. Automatic scanning is off until enabled. Initial discovery starts from onboarding time; use Import Historical Slips to choose an earlier date.
2. Add account profiles in Settings if desired. These are local profiles, with no connection to the bank. Masked suffixes and holder names never establish ownership by themselves.
3. Choose Import Photos. The system picker works without full-library access. Android also accepts image sharing from other apps. iOS includes a Share extension that stages explicitly shared images in an encrypted App Group inbox; open SlipTrack to finish importing.
4. On Scan center, optionally enable automatic scanning and grant full or selected-photo access. Review the scope and historical date before enabling.
5. Open an imported transaction, compare it with the receipt, correct fields, choose its direction/category/account and confirm. Until confirmation, it is excluded from all financial totals. Failed OCR can be retried or converted to a manual review record.

No real receipt photos or personal identifiers from the supplied examples are committed to the project. Tests use synthetic identities and references while preserving relevant label patterns.

## Implemented behavior

- Material 3 light/dark themes, GoRouter navigation, Riverpod data providers, mobile navigation and a wider-screen rail.
- Onboarding, dashboard, account creation, searchable/filterable transaction history, receipt review/edit/delete, scan center, spending analytics and settings.
- Separate THB/MMK monthly totals. Confirmed internal transfers are excluded from income and expenses. Analytics has daily/weekly/monthly expense groups and category/bank distributions.
- Exact integer minor-unit arithmetic. English/numeric date parsing, Thai Buddhist Era conversion, Thai/Myanmar digit normalization and abbreviated/local month parsing. Receipt wall-clock times and provider-based IANA timezone defaults are stored separately; no currency conversion is performed.
- Provider parser interfaces and KBZ/TrueMoney rules based on the supplied receipt structures. KBank is a provisional generic label parser, pending real authorized samples. Bank logos alone are insufficient; ambiguous provider matches are not auto-imported.
- On-device Android bundled Latin ML Kit and iOS Vision OCR, block bounds normalized to top-left coordinates, available engine confidence, script detection of recognized output, and a manual correction fallback.
- Android MediaStore/ContentObserver, Photo Picker and WorkManager discovery hints. iOS PhotoKit observation/full/limited permission support, PHPicker and encrypted Share extension inbox.
- Durable encrypted queue, paged media discovery, indexed queue states, pause/resume, failed-item retry, permission rechecks, checkpoints and catch-up after restart/resume. Source ID/content hash/provider reference checks prevent repeat imports; uncertain composite/reference conflicts remain reviewable.
- Drift/SQLite encrypted record payloads, HMAC search digests, schema migrations and indexes. Device-protected keys, optional biometric/device lock, password-encrypted local backup/restore and data deletion.
- English UI with Burmese/Thai primary navigation, action and form labels. Some longer notices, status messages, accessibility copy and enum labels currently fall back to English; full linguistic QA is a release gate.

## Layout

```
lib/app/                         bootstrap, theme, routing, providers
lib/core/                        money/models, encryption, backup, strings
lib/database/                    Drift custom SQL, migrations, repository
lib/features/accounts/           local account profiles
lib/features/gallery_scanner/    durable scan controller and scan screen
lib/features/ocr/                OCR and native photo channel contracts
lib/features/slip_recognition/   institution parsers and ownership classification
lib/features/transactions/       history, filters and review
lib/features/dashboard/          currency-separated monthly overview
lib/features/analytics/          spending groups
lib/features/settings/           privacy, backup, appearance and app lock
lib/shared/                      reusable UI and localization widgets
android/app/src/main/kotlin/     MediaStore, Photo Picker, ML Kit, WorkManager
ios/Runner/                      PhotoKit, PHPicker, Vision bridge
ios/ShareExtension/              explicit Share Sheet import UI
ios/Shared/                      authenticated encrypted share inbox
test/                            synthetic parser, database, scanner and UI tests
```

Financial records are AES-GCM encrypted before custom Drift SQL writes. Schema version 2 adds keyed duplicate lookup indexes to the encrypted version-1 entities; version 3 adds an indexed work-state column, with encrypted queue state reconciliation. No code generation is required. Totals/filtering decrypt records in memory; very large transaction histories will need further paging/aggregation performance work before deployment at scale.

## Release work and real samples

Production readiness requires native device validation, release signing, store photo-permission approval, full localization QA and an expanded authorized receipt corpus. Needed samples include real KBank/K PLUS layouts (Thai and English), incoming/outgoing/self-transfer variants for all three providers, complete versus masked identifiers, fees/refunds, older versions, long references, BE dates, non-Latin text and low-quality/rotated images. The two supplied sample structures are not evidence of general OCR accuracy. No accuracy percentage is claimed.

Android background OCR/import is not implemented as a headless Flutter worker: the worker provides a deferred discovery hint and foreground catch-up performs extraction. iOS performs observation/import while running and catch-up when reopened. See the platform document for precise boundaries.


#   s l i p t r a c k  
 