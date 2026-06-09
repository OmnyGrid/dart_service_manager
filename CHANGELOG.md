## 1.0.0

Initial release.

- Declare services in a package's `pubspec.yaml` via a `dart_services:` section.
- Compile service entrypoints to native executables with `dart compile exe`,
  cached and rebuilt on change.
- Install, uninstall, start, stop, pause, resume, restart and query services
  through the `DartServiceManager` Dart API and the `dart-service` CLI.
- Platform drivers for Linux (systemd), macOS (launchd) and Windows (SCM)
  behind a single `PlatformServiceDriver` abstraction.
- User- and system-scoped installation (`ServiceScope`), defaulting to user.
- A persistent JSON service registry behind a `ServiceRegistry` repository
  abstraction, with atomic writes and per-platform storage locations.
- Structured, injectable logging (`ServiceLogger`, `LogLevel`).
- Sealed exception hierarchy with stable, machine-readable error codes.
