# Validation record

Date: 18 October 2026. Host: Windows. SDK: Flutter 3.47.7 / Dart 3.13.5.

## Executed checks

- `flutter analyze` (via `scripts/check.ps1`): **passed, no issues**.
- `flutter test` (same Flutter test runner, through a short Windows Dart executable path): **31 tests passed**.
- Native XML parsing: main/release Android manifests, iOS plists and entitlements: **passed**.
- Xcode project syntax/structure parsing: **passed**. Runner links shared encryption source, depends on SlipTrackShare and embeds its extension product. This is not Swift compilation.
- Android debug APK compilation: **passed**. The real Kotlin bridges, ML Kit, WorkManager and native dependency builds compiled. Windows SDK-path/temporary-socket issues are handled by `scripts/build-android.ps1` with JDK 17. Signed private release APK validation is recorded below.
- iOS compilation: **not run**. This Windows host cannot run Xcode. A macOS simulator-build job is included in CI but has not been run here.
- Physical Android/iOS integration and OCR on real bank images: **not run**. No accuracy claim or native device-test success is implied by the unit/widget tests.

## Automated coverage

The suite uses synthetic text, fake authorized media lists/OCR failures, real in-memory SQLite via Drift and real AES-GCM/PBKDF2 cryptography. It does not simulate a successful real native OCR run.

| Requested coverage | Implemented check |
|---|---|
| TrueMoney extraction | Supplied label structure, synthetic payer/payee, masked IDs, THB amount, timestamp/reference |
| KBank extraction | Provisional generic label contract, BE timestamp; official layout unverified |
| KBZ extraction | Debit amount, MMK, transfer recipient, reference and note |
| THB and MMK parsing | Exact hundredths, separators, English/Thai/Myanmar digits, invalid precision |
| Thai date conversion | BE year, Thai and Myanmar month/digit normalization, invalid calendar day |
| Duplicate media | Same source ID, content hash and distinct asset IDs |
| Duplicate references | Same provider/reference, conflicting amounts preserved for review |
| Internal transfers | Exact institution/currency/account endpoint matches, excluded from totals |
| Unknown direction | Names and masked suffixes do not establish ownership |
| OCR failures | Durable failed item, successful retry, manual-review fallback |
| Missing fields | No fabricated amount/date, cannot confirm incomplete record |
| Permission denied | No library reads; system-picker path remains usable |
| Limited access | Only the returned authorized IDs processed |
| Restart/checkpoint | New controller resumes stored queue, does not re-OCR completed item; permission-upgrade catch-up |
| Background restrictions | Queue processing deferred while paused/backgrounded |
| Currency totals | Confirmed-only, separate THB/MMK, exclude internal transfers |
| Migrations | Existing encrypted v1 account survives upgrade to v3; new duplicate lookups work |
| Encryption | No readable financial fields in stored payload; wrong row AAD fails authentication |
| Backups | Restore accounts/transactions with a different device key; wrong password rejected |
| Monthly isolation | Main totals and recent receipts switch between months without mixing; the next history screen contains both months |
| Real UI/database flow | 390×844 dashboard → history → receipt review → confirmation updates persisted totals |

The mobile widget flow found and fixed a real narrow-screen dropdown overflow.

## Required physical-device checks

1. Android 12 storage access, Android 13 full access and Android 14+ selected-photo access; revoke/regrant while scanning; confirm only granted media is read.
2. Both OS system pickers with permission denied/limited/full, iCloud-only or deleted images, temporary grants, URI persistence and app restarts.
3. Import the actual authorized KBZ/TrueMoney samples; inspect amount, date, sender/payee, notes, references and orientation; add genuine KBank samples before declaring layout support.
4. Native OCR on English, Thai and Myanmar receipts. Confirm unsupported fields stay reviewable, and never infer missing-script support from language detection.
5. Foreground observer events, rapid additions, large libraries, pagination, process termination, queue recovery, paused scans and Android battery/WorkManager deferral.
6. App Group/Keychain provisioning and iOS Share extension lifecycle; verify staged original images are encrypted, user-authorized and removed after confirmation/deletion.
7. Biometric/device lock, authentication cancel/failure, background/resume, screenshot/app-switcher privacy and device key invalidation.
8. Native backup save/open pickers, user cancel, wrong password, full roundtrip and cleanup of temporary encrypted exports.
9. Run Android lint, inspect the merged release manifest for permissions, configure private release signing and validate a release APK on hardware. Run iOS simulator and signed device builds with Xcode, including the extension.
10. Complete Burmese/Thai language review, long translated strings, accessibility/text scaling, dark mode and wide layouts.

The CI workflow is provided as a reproducible check definition, not evidence that its Android/iOS jobs have already succeeded.


