# ai_powerd_mobile_code_assitant

A Flutter prototype for a mobile-first AI coding coach covering project slices,
data structures, and LeetCode practice.

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

Point Flutter at the proxy instead of Judge0 directly:

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
