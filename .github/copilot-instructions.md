# Copilot instructions (OnlyStudy)

## Project map & architecture
- Flutter app: entrypoint in `lib/main.dart` (initializes `MediaKit`, `DownloadService`, cache cleanup, `SettingsService`, then routes to `MainScreen` or `LoginScreen`).
- UI is mostly “screen-driven” with direct service calls (no Provider/BLoC): see `lib/screens/*`.
- Bottom navigation container uses `IndexedStack` in `lib/screens/main_screen.dart`.

## Key user flows (follow existing patterns)
- Login: `LoginScreen` shows QR code and polls (`AuthService.generateQRCode/pollLoginStatus`) then saves cookie params via `AuthService.saveLoginInfo`.
- Home: `HomeScreen` loads visible folder/season IDs from `AuthService`, fetches metadata via `BiliApiService`, and syncs first page of videos into local DB for search (`DatabaseService.insertVideos`).
- Player: `VideoPlayerScreen` uses `media_kit` Player + `media_kit_video`; gets `VideoDetail` then `getVideoPlayUrl`; reports progress every 5s via `BiliApiService.reportHistory` and adds local history via `HistoryService`.
- Offline cache: `DownloadService` persists tasks in `downloads.db` and streams updates via `tasksStream`; UI in `lib/screens/download_screen.dart`.

## Services & persistence conventions
- Services are singletons (`static final _instance` + `factory ...() => _instance`): keep this style when adding new services.
- Persistent storage:
  - Auth/session & UI locks use `SharedPreferences` in `lib/services/auth_service.dart`.
  - App settings use `SharedPreferences` in `lib/services/settings_service.dart` and expose a `ValueNotifier<Locale?>` for dynamic locale.
  - Watch history uses `SharedPreferences` list of JSON strings in `lib/services/history_service.dart`.
  - Search cache uses `sqflite` table `videos` in `lib/services/database_service.dart`.
- Network:
  - Bilibili API requests go through `Dio` in `lib/services/bili_api_service.dart` with fixed `User-Agent` + `Referer` and Cookie from `AuthService.getCookieString()`.
  - When adding or debugging Bilibili endpoints/params, use https://github.com/SocialSisterYi/bilibili-API-collect as the primary reference.

## Localization & theme
- Localization uses Flutter gen-l10n (`l10n.yaml`): arb files in `lib/l10n/` (template is `app_zh.arb`).
- App theme is Material 3 dark-only (`AppTheme.darkTheme` in `lib/theme/app_theme.dart`). Avoid adding a separate light theme unless the feature explicitly requires it.

## Developer workflows
- Install deps: `flutter pub get`
- Generate l10n: `flutter gen-l10n`
- Run app: `flutter run`
- Tests: `flutter test` (example widget test in `test/settings_screen_test.dart` uses `SharedPreferences.setMockInitialValues`).

## Testing & refactor expectations
- It’s OK to do small, adjacent refactors while implementing features (keep changes scoped and consistent with existing screen-driven patterns).
- Widget tests may assert on localized strings; set an explicit `locale` on `MaterialApp` or derive expected text from `AppLocalizations` instead of hard-coding.

## Change hints (project-specific)
- If you add a new setting:
  - Add key + load/save in `lib/services/settings_service.dart`.
  - Surface it in `lib/screens/settings_screen.dart`.
  - Consider adding/adjusting a widget test like `test/settings_screen_test.dart` when behavior depends on prefs.
- If you add API calls, keep cookie/header behavior consistent with `BiliApiService` and prefer returning typed models from `lib/models/bili_models.dart`.

## Code comment & UX copy rules
- Comments must be in Chinese; no English comments or inline comments.
- Every function (including getters/setters) needs a concise Chinese doc comment stating its purpose.
- User-facing UI copy (non-debug) must be localized via existing l10n strings or added to `lib/l10n/`.
