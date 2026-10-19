# Platform behavior and OCR limitations

## Android

- Minimum SDK 24. The bundled `com.google.mlkit:text-recognition:16.0.1` Latin model is packaged with the app; it does not require a model download at first recognition.
- Full library discovery requests READ_MEDIA_IMAGES on Android 13+, READ_EXTERNAL_STORAGE through Android 12, and READ_MEDIA_VISUAL_USER_SELECTED for Android 14+ partial access. Permissions are checked before discovery and again on reads by ContentResolver.
- The full-access toggle is optional. Google Play broad photo access is subject to its review/policy requirements; it is not guaranteed. Keep picker-only operation available and, if broad permission is not approved, remove the library permission declarations in the distribution manifest and disable automatic scanning for that distribution.
- PickMultipleVisualMedia uses the system picker (or its document-picker fallback). Persistable URI grants are requested when available. Repeated events do not re-run completed queue items.
- ContentObserver events while the activity/engine is alive are debounced. A battery-conscious 15-minute WorkManager task supplies a discovery hint with full access; Android may delay or stop it. The worker does not run OCR, decrypt records or promise financial import while terminated. Catch-up on foreground processes the durable queue and authorized library changes.
- MediaStore discovery uses DATE_ADDED for incremental discovery and DATE_TAKEN with DATE_ADDED fallback for the user-selected historical cutoff. Pages are limited to 100. Library changes during pagination, permission regrants and OEM ordering need device stress tests.
- Permission upgrades reset discovery scope; limited access is re-enumerated to catch newly selected old images. Already queued images are not repeatedly OCR'd.
- Source images are read through granted content URIs. No permanent gallery copy is made. If access is lost or the source is deleted, saved transactions remain and the review screen reports the unavailable source.
- ACTION_SEND image imports are supported. Some senders provide temporary grants only; review while the grant is available or reimport through Photo Picker.
- The release manifest removes transitive INTERNET permission. Debug/profile Flutter tooling still needs network permission for its development service. Inspect the final merged release manifest before distribution.

## iOS

- Minimum deployment target 15. PhotoKit requests read/write authorization for read access and never modifies the library. Full and limited access are supported; a Manage selected photos button invokes the system limited-library picker.
- PHPhotoLibraryChangeObserver handles changes while the app is running. There is no unsupported background mode and no promise of continuous detection after termination.
- Catch-up queries authorized assets using creation/modification dates and a persisted checkpoint. Limited access re-enumerates accessible assets so newly selected older photos are discovered.
- PHImageManager requests disallow network downloads. An iCloud-only asset not locally available may fail and require an explicit picker import once available on the device.
- PHPicker works without full library permission. Accessible PHAsset identifiers are retained. If only item-provider data is available, that image stays in memory for the current session; the user should finish review or reselect it after app termination. It is not copied unencrypted to permanent app storage.
- The Share extension stages images only after the user presses Import receipt. Originals are AES-GCM encrypted in an excluded-from-backup App Group inbox, with a shared device-only Keychain key. The host imports on next launch/resume; it does not forcibly open itself from the extension. Encrypted staged images remain until confirmation/deletion. App Group and Keychain signing capabilities must match both targets.
- The host database vault key uses the app's private Keychain group; the extension has only its separate shared-inbox group.
- Final Swift compilation, extension signing, picker lifecycle, Face ID and physical-device behavior require macOS/Xcode and real-device validation. Parsing a project file does not prove a successful native build.

## OCR language matrix

| Engine | English/Latin | Thai | Myanmar |
|---|---|---|---|
| Bundled Android Latin ML Kit | Implemented | Not provided by this model | Not provided by this model |
| iOS Vision | Requested when runtime supports it | Requested only if returned by supportedRecognitionLanguages | Requested only if returned by supportedRecognitionLanguages |
| Manual review | Available | Available | Available |

Language identification in Dart detects scripts in the OCR output. It is not an OCR engine and is never used to claim recognition of a missing script. Android aggregate confidence is null when not supplied. iOS returns actual Vision candidate confidence. Parser completeness is a field-presence heuristic, not a calibrated financial accuracy score. All imports require human confirmation regardless of score.

No alternative Thai/Myanmar model has been bundled or validated. The functional fallback is manual review/entry from the source, including an explicit manual path after OCR errors. To add an offline model, implement OCRService and ship/license/test its language assets before claiming support. Orientation is delegated to the native image/OCR frameworks; thumbnail resizing is nondestructive. Contrast/denoising/region-cropping preprocessing is not currently implemented.

## References checked during implementation

- [ML Kit scripts/languages](https://developers.google.com/ml-kit/vision/text-recognition/v2/languages)
- [Bundled Android recognition integration](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)
- [Android Photo Picker and persistent grants](https://developer.android.com/training/data-storage/shared/photo-picker)
- [Android selected-photo access](https://developer.android.com/about/versions/14/changes/partial-photo-video-access)
- [WorkManager releases](https://developer.android.com/jetpack/androidx/releases/work)
- [Vision recognition API](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- [Flutter iOS app extensions](https://docs.flutter.dev/platform-integration/ios/app-extensions)

## Local spending alerts and pay-cycle gate

Both native media channels support `notificationPermission` (queries without prompting unless `request: true`) and `notifyBudget` (returns whether the OS accepted a local notification request). iOS requests alert/sound authorization and presents SlipTrack budget banners in the foreground. Android declares POST_NOTIFICATIONS, requests runtime permission on API 33+, uses a dedicated notification channel, respects blocked channel/app settings, and opens SlipTrack when tapped. No notification-listener service or remote push entitlement is used.

Dart persists thresholds per 25th-to-25th cycle and uses a separate stable notification ID for each threshold. Permission denial or a rejected request does not mark a threshold as sent. OS acceptance does not guarantee a visible banner: Focus, user settings and OS policies still apply. Threshold checks are foreground/resume and record-change driven; there is no background headless financial worker.

OCR processing, including queued shares, requires confirmed manually entered income in the current cycle. Sources can remain queued until income is recorded. This gate does not delete any existing receipts or photos.
