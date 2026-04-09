# AGENTS.md

## Core Commands
- `flutter pub get`
- `flutter run`
- `flutter analyze`
- `flutter test`
- Single test: `flutter test test/settings_screen_test.dart`
- After changing any `lib/l10n/*.arb` string, run `flutter gen-l10n` before analysis/tests.

## Entry Points And App Shape
- App entrypoint is `lib/main.dart`.
- Startup order in `main()` matters: `MediaKit.ensureInitialized()` -> `DownloadService().init()` -> `CacheService().checkAndClearCache()` -> `initAudioService()` -> `SettingsService().init()` -> auth check -> `MainScreen` or `LoginScreen`.
- Main navigation is an `IndexedStack` in `lib/screens/main_screen.dart`; screens are kept alive when switching tabs.
- Theme is dark-only Material 3 via `AppTheme.darkTheme`; `MaterialApp` sets `themeMode: ThemeMode.dark`.

## Persistence And Data Flow
- Services follow a repo-wide singleton pattern: `static final _instance`, private constructor, `factory ...() => _instance`.
- `AuthService.logout()` calls `SharedPreferences.clear()`, so logout also wipes settings, locale, lock state, and other prefs-backed data.
- Search is local-first, not live API search: `HomeScreen` syncs only the first page of visible folders/seasons into `onlystudy.db`, and searches that sqflite cache through `DatabaseService.searchVideos(...)`.
- There are two local databases: `onlystudy.db` for searchable video cache and `downloads.db` for offline download tasks.
- Desktop DB access uses `sqflite_common_ffi`; `DatabaseService` switches to FFI on Windows/Linux.

## Bilibili-Specific Constraints
- Bilibili API traffic is centralized in `lib/services/bili_api_service.dart` and uses fixed `User-Agent`, `Referer`, and auth cookie headers; keep new endpoints consistent with that service instead of creating ad hoc clients.
- Login is QR-based through `AuthService.generateQRCode()` and `pollLoginStatus()`; successful login saves cookie params from the callback URL into `SharedPreferences`.

## Localization And UI Copy
- Localization is generated with `l10n.yaml` from `lib/l10n/app_zh.arb` and `lib/l10n/app_en.arb`; generated `lib/l10n/app_localizations*.dart` files are part of the repo.
- User-facing strings are expected to come from `AppLocalizations`; avoid hard-coded UI text in widgets.

## Testing Notes
- The only committed test is `test/settings_screen_test.dart`; it is a widget test that depends on `SharedPreferences.setMockInitialValues(...)` and an explicit `locale` on `MaterialApp`.
- If you add prefs-backed settings or locked-folder flows, extend that style of widget test instead of relying on live prefs state.

## Release And Build Facts
- CI release workflow is `.github/workflows/flutter_release.yml` and only runs on pushed tags matching `v*`.
- CI uses Flutter `3.38.4`.
- Android release command in CI: `flutter build apk --release --split-per-abi --obfuscate --split-debug-info=./debug-info`
- Linux release builds require system packages first: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libasound2-dev libmpv-dev`.
