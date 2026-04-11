# ai_powerd_mobile_code_assitant

A Flutter prototype for a mobile-first AI coding coach covering project slices,
data structures, and LeetCode practice.

## Synced App Data

The app now bootstraps from repository-backed data instead of calling
`AppState.seeded()` at runtime.

- `lib/services/app_api_service.dart` talks to the learner-data API.
- `lib/repositories/*` own catalog refresh, learner bootstrap, and outbox sync.
- `lib/storage/local_app_store.dart` keeps a cached snapshot plus pending sync
  events so the app can reopen quickly and retry sync later.
- `app-api/` now contains the learner-state API plus a custom responsive admin
  web for managing content.
- `strapi/` remains as migration/reference material from the earlier CMS-based
  plan, but the active direction is the custom admin in `app-api/public/admin`.

### Run the learner-state API and admin

Provide a catalog snapshot at `strapi/seed/seed_content.json` first.
The repo includes:

- `tool/export_seed_content.dart` to serialize the legacy seed curriculum
- `strapi/importers/upsert-seed-content.mjs` to push that snapshot into Strapi

Then install and run the app API:

```bash
cd app-api
npm install
BOOTSTRAP_CATALOG_PATH=../strapi/seed/seed_content.json npm start
```

Point Flutter at it with:

```bash
flutter run \
  --dart-define=APP_API_BASE_URL=http://127.0.0.1:8788 \
  --dart-define=SANDBOX_API_BASE_URL=http://127.0.0.1:8787
```

Open the admin web at [http://127.0.0.1:8788/admin](http://127.0.0.1:8788/admin).
Set `ADMIN_API_KEY` before `npm start` if you do not want to use the local
default key.

## Sandbox Proxy MVP

`Build` and `Run` now go through a thin sandbox proxy that calls Judge0 on the
server side. `Check` still runs locally with the existing regex-based
acceptance checks, so the practice loop stays fast even without the network.

### Start the sandbox proxy

Install and run the proxy:

```bash
cd server
npm install
JUDGE0_BASE_URL=https://ce.judge0.com npm start
```

If your Judge0 host requires auth:

```bash
cd server
JUDGE0_BASE_URL=https://your-judge0-host \
JUDGE0_AUTH_TOKEN=your-token \
JUDGE0_AUTH_HEADER=X-Auth-Token \
npm start
```

The proxy exposes:

- `GET /health`
- `POST /api/sandbox/execute`

### Run the Flutter app

Debug builds now auto-fall back to a local proxy when no
`SANDBOX_API_BASE_URL` is provided:

- iOS simulator / macOS: `http://127.0.0.1:8787`
- Android emulator: `http://10.0.2.2:8787`

That means `Build` and `Run` work locally as soon as the proxy is running.
You only need `--dart-define` when targeting a real device or a non-default
host.

To override the default and point Flutter at a different proxy:

```bash
flutter run \
  --dart-define=SANDBOX_API_BASE_URL=http://127.0.0.1:8787
```

Use the IP or hostname that your simulator/device can reach. For example,
Android emulators often need `http://10.0.2.2:8787`.

### MVP notes

- The mobile app no longer holds Judge0 credentials.
- The proxy resolves Judge0 `language_id` dynamically from the `/languages`
  endpoint and applies basic rate limiting.
- `Run` executes multiple test cases per milestone through a harness template,
  so class-only and function-only exercises can still be validated meaningfully.
- The proxy now forwards extra non-entry files through Judge0 `additional_files`
  so Python helpers and similar sidecar files can participate in execution.
- `Build` also goes through the proxy. For interpreted languages like Python,
  this is closer to a syntax/startup validation pass than a true compile-only
  step.
- Result sheets now separate `Cases`, `Stdout`, `Stderr`, `Compile`, and
  `Message` when the proxy returns those channels.
- The session screen also keeps a short in-app history of recent build and run
  attempts.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

To validate the proxy file itself:

```bash
node --check server/index.js
```

To run the proxy integration tests:

```bash
cd server
npm test
```
