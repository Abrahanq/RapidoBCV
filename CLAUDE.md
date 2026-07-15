# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

RápidoBCV (Dart package name `venezuela_dolar`) is a Flutter app that shows official/parallel USD, EUR and USDT exchange rates for Venezuela (BCV + Binance P2P), with a converter and calculator. Targets Android, iOS, Web, Windows, Linux, macOS. Android `applicationId`/`namespace` is `com.abrahanq.rapidobcv` (the README describes an older `com.rapidobcv.app` naming, now stale).

## Commands

Use the `Makefile` shortcuts (thin wrappers over the Flutter CLI):

```bash
make get              # flutter pub get
make run              # flutter run (debug)
make analyze          # flutter analyze
make test             # flutter test
make build-apk        # flutter build apk --release
make build-appbundle  # flutter build appbundle --release
make build-ios        # flutter build ios --release
make clean            # flutter clean
make devices          # flutter devices
```

Run a single test: `flutter test test/widget_test.dart`.

Note: `test/widget_test.dart` is the unmodified default Flutter counter-app template test — it does not test anything in this app and currently fails against the real `MyApp` (which has no counter). There is no other test coverage. Don't assume `flutter test` passing/failing reflects app correctness; if adding real tests, replace this file's content.

Web build for GitHub Pages deploy (mirrors `.github/workflows/deploy_web.yml`):
```bash
flutter build web --release --base-href "/rapidoBCV/"
cp docs/privacy.html build/web/privacy.html
```

Android release signing: requires `android/key.properties` (gitignored, not present by default) pointing at an upload keystore. See README.md for the one-time setup. Before each release bump `version:` in `pubspec.yaml` (`X.Y.Z+build`, build number must always increase).

## Architecture

All app code lives directly in `lib/` (no subfolders):

- `lib/main.dart` — `MyApp` root widget. Loads two persisted prefs via `shared_preferences` on boot: dark/light theme (`theme_is_dark`) and which UI to show (`ui_classic`). It switches between two entirely independent, self-contained screen implementations of the same feature — `TasaScreen` (default, `lib/tasa_screen.dart`) and `ConversorPage` (legacy/alternate, `lib/classic_screen.dart`). Both take `onToggleTheme`/`onToggleUI` callbacks from `MyApp` so either screen can flip theme or switch UI. When changing shared behavior (rates fetching, caching, widget updates), check both files — logic is duplicated, not shared, between the two screens.
- `lib/rates_service.dart` — `RatesService`, the only data-layer class, used by both screens. Responsibilities:
  - `fetchPrices()`: fetches BCV/parallel history from `https://abrahanq.github.io/bcv-price/prices.json` (a static JSON published from a separate repo, not this one).
  - `fetchUsdtQuoteWithCache()` / `fetchUsdtFromBinance()`: fetches USDT/VES P2P buy & sell averages directly from Binance's public P2P search API (`p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search`), routed through `corsproxy.io` on web builds (`kIsWeb`) to sidestep CORS. Results are cached in `SharedPreferences` for 1 hour; a versioned cache key (`usdt_quote_cache_version`) exists because buy/sell were swapped in a past cache format — old caches are auto-corrected on read.
  - `cacheRates()` / `readCachedRates()`: last-known-good rates cache so the app has something to show offline/on error.
  - `updateHomeWidget()`: pushes formatted values to the native Android home-screen widget via the `home_widget` package.
  - `initialIndex()` / `rateForWidget()`: pick which historical rate entry to show by default (today's rate on weekdays, most recent on weekends).
- `lib/tasa_screen.dart` (~2000 lines) — the primary UI (`TasaScreen`/`_TasaScreenState`). Contains its own design-token system (`_TC` color tokens, `_AccentPreset` list of selectable accent colors persisted by the user), a rate history browser, a currency converter/calculator (`_CalcItem`, `_CalcInputRow`, `_CurrencyCard`), screenshot/share support (`screenshot` + `share_plus`), and a first-run spotlight/tutorial overlay (`_SpotlightPainter`).
- `lib/classic_screen.dart` (~1200 lines) — the older/alternate UI (`ConversorPage`), reachable via the in-app UI toggle. Simpler layout: `_RatesPanel`, `_ConverterPanel`, `_UsdCalculatorPanel`.
- `android/app/src/main/kotlin/.../RapidobcvWidgetProvider.kt` — native Android home-screen widget (App Widget), fed by `RatesService.updateHomeWidget()` via `home_widget`'s shared storage bridge. Layout in `android/app/src/main/res/layout/rapidobcv_widget_layout.xml`, config in `.../xml/rapidobcv_widget_info.xml`.

### Networking notes
- No backend of this project's own; all data comes from two third-party endpoints (a GitHub Pages JSON feed and Binance's public P2P API). Both calls have hardcoded 10s timeouts and are expected to fail sometimes — always keep fallback-to-cache paths intact when touching this code.
- Binance calls are POST requests with a fixed VES/USDT P2P search payload; buy vs. sell price is determined by `tradeType` (`SELL`/`BUY`) and each is the arithmetic mean of up to 20 merchant ads.

### Privacy policy / Pages deploy
`docs/privacy.html` is the source of truth for the privacy policy; the `deploy_web.yml` workflow copies it into the built web app on every push to `main` and publishes to the `gh-pages` branch, served at `https://abrahanq.github.io/rapidoBCV/`. This URL is also referenced from Play Console. See `PRIVACIDAD.md` for the Spanish-language privacy policy source content.
