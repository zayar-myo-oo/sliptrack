# Validation record

## 19 October 2026 — macOS continuation

Latest UI/data continuation: `flutter analyze` passes and **53 tests pass**. The final signed iOS release build passed and the private update was installed on the connected iPhone without deleting app data. The palette is now neutral graphite/white with muted blue accents; summary text, cards and buttons are smaller. The companion is a code-drawn animated cat with pointed ears, whiskers and a swaying tail, preserving the existing moods/reward state.

Navigation uses one persistent shell and opaque Material content clipped to its bounds. All in-app routes use `NoTransitionPage`; tab changes no longer slide transparent scroll views across each other or animate duplicate navigation bars. The iOS widget variant switches Analytics → Settings with 16 ms pumps and verifies only the new page and one shell are visible.

Manual expense creation is available from Overview and encrypted records retain an explicit `isManualExpense` flag. Older JSON defaults this flag to false. No database rebuild or destructive schema migration is required. Tests cover the Sep 25 income continuing through Oct 24, confirmed manual expenses in that cycle, and exclusion of Oct 25 records.

Settings → Manage data previews counts by type and can delete imported receipts, manual income, manual expenses or savings independently, for one selected pay cycle or all dates. Confirmation is required in the app; no user financial data was cleared during development. Tests cover cancel/confirm in the real UI, preservation of unselected records/settings, queue/duplicate-index cleanup for re-import, and retained cat rewards after savings deletion.


Host: macOS with Xcode 27.0, Flutter 3.47.7 / Dart 3.13.5.

- `flutter analyze`: passed with no issues.
- `flutter test`: 49 tests passed, including the new pay-cycle, income-gate, notification-controller, savings and mobile import flows.
- `flutter build ios --release --no-codesign`: passed; compiles the Swift notification bridge and Share extension. `flutter build ios --release` also passed with the existing development team, and the resulting private update was installed on the connected iPhone under the same bundle identifier.
- `flutter build apk --debug`: passed; compiles the Kotlin permission/notification channel/posting handlers.
- Generated and visually inspected synthetic 390×844 UI captures in ignored `build/ui-review/` (Overview, Scan, Review). These are test-renderer previews, not screenshots of the user's financial records.

New regression coverage:

- 25th inclusive / next 25th exclusive boundaries, year rollover and leap February; extra income stays in the existing cycle.
- No photo picker, gallery discovery or queued/shared OCR until confirmed manual income exists in the active cycle; the next 25th requires new income.
- Confirmed-only 80% / 100% alerts, both thresholds when crossed together, month/cycle rollover, denial/failure retries, overlapping evaluations and deduplication after controller restart.
- Original MMK amounts remain intact while the offline rate supplies approximate THB budget comparisons.
- Savings snapshots, encrypted persistence/portable backup, level-10 cap, later outfits and reward retention after immediate savings deletion.
- Income entry → system-picker service → OCR/parser → extracted review form → save pending → visible queue → re-pick existing receipt → confirmation → persisted period totals. Media/OCR services are fake; this does not claim real native OCR accuracy.
- Centered companion remains visible in editors and Analytics; tapping it returns to Overview.
- Reduced-motion navigation tests; continuous companion animation no longer causes tests to wait indefinitely.
- Legacy v1 migration fixture now models the actual old schema and verifies upgrade to v4.

The latest user requirement supersedes calendar-only budgeting: the default budget cycle is now the 25th to the following 24th. Calendar month remains a separate, strictly isolated view. Savings remain explicit entries rather than inferred net income.

Still requires physical-device validation: actual KBZ/TrueMoney images, native notification permission/foreground banner/tap behavior, share extension import and native backup pickers. KBank remains provisional. No real receipts, signing secrets or financial databases were added to source control.

## Earlier Windows baseline

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



## Salary-date and automatic import update
- Local Apple Vision extraction on all three user-supplied images produced the expected dates/times and amounts. The two TrueMoney representations share a reference and represent one transaction. Images and raw OCR outputs remain outside the repository.
- Added checks for open salary periods past the 25th, next-salary boundaries, extra income, encrypted savings reserves, unchanged actual savings, OCR column ordering and split timestamps.
- iPhone-sized integration coverage now verifies savings reservation and immediate import totals without per-receipt confirmation. Album discovery is implemented natively for PhotoKit collections and Android MediaStore buckets; live user-library album selection still requires device interaction.
