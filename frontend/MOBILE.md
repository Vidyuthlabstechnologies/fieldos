# FieldOS Mobile App (Capacitor) — DEPRECATED

> **This approach has been superseded.** FieldOS's mobile strategy is now
> the native Flutter app at `fieldos_mobile/` — see
> [`docs/MOBILE_GUIDE.md`](../docs/MOBILE_GUIDE.md). It's more complete
> (its own offline auth, local database, and a full site-ops feature set)
> and, unlike this Capacitor wrapper, has been verified to actually build,
> analyze cleanly, and pass its test suite.
>
> `frontend/android/` and `capacitor.config.ts` remain on disk for
> reference but are not being actively developed. The content below is
> kept as-is for historical/reference purposes only — don't treat it as
> current guidance without re-verifying it first.

## Quick Start

```bash
cd frontend
npm run build
npx cap sync
npx cap open android
```

## Requirements

- Android Studio (latest)
- JDK 17+
- Android SDK 34+
- Node.js 18+

## Building Release APK/AAB

1. Open Android Studio:
   ```bash
   npx cap open android
   ```

2. Generate signed bundle:
   - Build → Generate Signed Bundle / APK
   - Choose Android App Bundle (.aab) for Play Store
   - Create new keystore or use existing

3. Or via CLI:
   ```bash
   cd android
   ./gradlew bundleRelease
   # Output: android/app/build/outputs/bundle/release/app-release.aab
   ```

## Permissions

The app requests:
- Camera (for document/inspection photos)
- Location (for geofence attendance)
- Microphone (for voice DPR)
- Storage (for offline sync)
- Internet (API access)

## Features Available in Mobile App

- ✅ Offline-first with Service Worker
- ✅ Camera integration for photos
- ✅ Voice recording for DPR
- ✅ GPS location for attendance
- ✅ Push notifications (future)
- ✅ Biometric auth (future)

## Configuration

- `capacitor.config.ts` - Main Capacitor config
- `android/app/src/main/AndroidManifest.xml` - Permissions
- `android/app/src/main/res/xml/file_paths.xml` - File provider paths

## Testing

```bash
# Run on connected device
npx cap run android

# Or build debug APK
cd android && ./gradlew assembleDebug
```

## Icons & Splash Screen

Generate adaptive icons:
```bash
# Add your icon to android/app/src/main/res/mipmap-*/ic_launcher.png
# Add splash to android/app/src/main/res/drawable/splash.png
```

## Troubleshooting

- **Cleartext traffic**: Enabled in manifest for local dev
- **FileProvider**: Configured for camera captures
- **Large files**: Use `android:requestLegacyExternalStorage="true"` if needed