# shelf_server example

An example package whose service is a real [Shelf](https://pub.dev/packages/shelf)
HTTP server, managed end-to-end by [`dart_service_manager`](../../).

The server is declared as a service in [`pubspec.yaml`](pubspec.yaml):

```yaml
dart_services:
  api:
    script: bin/server.dart
    description: Example Shelf HTTP API
    args: ['--port', '8080']
    env:
      LOG_LEVEL: info
```

It exposes three routes:

| Route | Response |
|-------|----------|
| `GET /` | greeting + uptime |
| `GET /health` | `ok` |
| `GET /metrics` | uptime and request count (plain text) |

## Run it directly

```bash
cd example/shelf_server
dart pub get
dart run bin/server.dart --port 8080      # or: PORT=8080 dart run bin/server.dart

# in another shell:
curl localhost:8080/
curl localhost:8080/health
curl localhost:8080/metrics
```

Press `Ctrl-C` to stop — the server shuts down gracefully on `SIGINT`/`SIGTERM`,
which is exactly how the service manager stops it.

## Run it as a managed OS service

From the repository root:

```bash
# Compile bin/server.dart to a native executable and install it as a service.
dart-service install shelf_server --path example/shelf_server

dart-service start  shelf_server:api
curl localhost:8080/health        # -> ok
dart-service status shelf_server:api   # -> running

dart-service stop      shelf_server:api
dart-service uninstall shelf_server
```

(If you haven't activated the CLI globally, replace `dart-service` with
`dart run dart_service_manager:dart_service` from the package root.)
