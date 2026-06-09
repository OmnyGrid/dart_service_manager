# dart_service_manager

[![Dart](https://img.shields.io/badge/Dart-3.x-blue.svg)](https://dart.dev)
[![Null safety](https://img.shields.io/badge/null--safety-sound-success.svg)](https://dart.dev/null-safety)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Declare services in a Dart package, compile them to native executables, and
install and manage them as **native operating-system services** — on Linux
(systemd), macOS (launchd) and Windows (Service Control Manager) — through a
first-class Dart API and a thin `dart-service` CLI.

It is a **library first**: the CLI is a small wrapper over the public
`DartServiceManager` API, the platform-specific code sits behind a single
driver abstraction, and every external process call is injectable, so the whole
thing is testable without touching a real init system.

```text
+-----------------------+
| CLI (dart-service)    |
+-----------------------+
            |
            v
+-----------------------+
| DartServiceManager    |   orchestration only
+-----------------------+
            |
            v
+-----------------------+
| PlatformServiceDriver |
+-----------------------+
      |      |      |
      v      v      v
   Linux  macOS  Windows
  systemd launchd  SCM
```

## Features

- **Declarative manifest** — list services in your package's `pubspec.yaml`.
- **Native compilation** — `dart compile exe`, cached and rebuilt on change.
- **Full lifecycle** — install, uninstall, start, stop, pause, resume, restart.
- **Status & inventory** — query live status; list services, packages, and a
  package's services.
- **Cross-platform** — systemd, launchd and Windows SCM behind one interface.
- **User or system scope** — per-user (no elevation, the default) or machine-wide.
- **Own registry** — a persistent, atomically-written JSON registry behind a
  repository abstraction, independent of OS discovery.
- **Clean, typed API** — sealed exceptions with stable codes, injectable
  structured logging, immutable value objects, constructor DI throughout.

## Platform support

| Capability | Linux (systemd) | macOS (launchd) | Windows (SCM) |
|------------|:---------------:|:---------------:|:-------------:|
| install / uninstall | ✅ | ✅ | ✅ |
| start / stop / restart | ✅ | ✅ | ✅ |
| status | ✅ | ✅ | ✅ |
| pause / resume | ➖ not supported | ➖ not supported | ✅ |

Pausing is only meaningful on Windows; on Linux and macOS `pause`/`resume`
throw `PlatformNotSupportedException`.

> **Windows note:** a plain compiled Dart executable does not implement a
> Windows service control dispatcher, so the SCM may report it as slow to
> respond to control requests. Wrapping the entrypoint in a service host makes
> control signals fully honoured.

## Declaring services

Add a `dart_services:` section to the target package's `pubspec.yaml`:

```yaml
name: analytics_server

dart_services:
  # Shorthand: service name -> entrypoint script.
  worker: bin/worker.dart

  # Map form: description, args and env are optional.
  scheduler:
    script: bin/scheduler.dart
    description: Periodic job scheduler
    args: ['--interval', '60']
    env:
      LOG_LEVEL: info

  monitor: bin/monitor.dart
```

See [`example/sample_package`](example/sample_package) for a runnable package.

## Getting started

```yaml
# pubspec.yaml
dev_dependencies:
  dart_service_manager: ^1.0.0
```

```bash
dart pub get
# install the CLI globally (optional)
dart pub global activate dart_service_manager
```

## Usage — CLI

```bash
# Install all services of a package (resolved from the cwd or package_config).
dart-service install analytics_server

# Install one service, system-wide, from an explicit path.
dart-service --scope system install analytics_server:worker --path ./analytics_server

# Lifecycle.
dart-service start   analytics_server:worker
dart-service status  analytics_server:worker
dart-service restart analytics_server:worker
dart-service stop    analytics_server:worker

# Inventory.
dart-service list
dart-service packages
dart-service services analytics_server

# Remove.
dart-service uninstall analytics_server:worker
```

Full command reference: [`doc/cli.md`](doc/cli.md).

## Usage — Dart API

```dart
import 'package:dart_service_manager/dart_service_manager.dart';

Future<void> main() async {
  final manager = DartServiceManager.forCurrentPlatform(
    logger: ConsoleServiceLogger(),
  );

  // Compile + install every declared service.
  await manager.install('analytics_server');

  // Or a single service, system-wide.
  await manager.install(
    'analytics_server',
    serviceName: 'worker',
    scope: ServiceScope.system,
  );

  await manager.start('analytics_server', 'worker');

  final status = await manager.status('analytics_server', 'worker');
  print('worker is ${status.name}'); // running

  for (final service in await manager.listServices()) {
    print('${service.qualifiedName}: ${service.status.name}');
  }

  await manager.stop('analytics_server', 'worker');
  await manager.uninstall('analytics_server');
}
```

### Core API

```dart
Future<void> install(String package, {String? serviceName, ServiceScope scope, String? path});
Future<void> uninstall(String package, {String? serviceName});
Future<void> start(String package, String service);
Future<void> stop(String package, String service);
Future<void> pause(String package, String service);
Future<void> resume(String package, String service);
Future<void> restart(String package, String service);
Future<ServiceStatus> status(String package, String service);
Future<List<DartPackageService>> listServices();
Future<List<String>> listPackages();
Future<List<DartPackageService>> listPackageServices(String packageName);
```

Every dependency is constructor-injectable for embedding and testing — see the
default `DartServiceManager` constructor versus `DartServiceManager.forCurrentPlatform`.

## Where things are stored

| | Registry & binaries |
|---|---|
| Linux | `$XDG_DATA_HOME` or `~/.local/share/dart_service_manager/` |
| macOS | `~/Library/Application Support/dart_service_manager/` |
| Windows | `%LOCALAPPDATA%\dart_service_manager\` |

Generated unit files / plists live in the per-scope OS locations
(`~/.config/systemd/user`, `~/Library/LaunchAgents`, `/etc/systemd/system`,
`/Library/LaunchDaemons`).

## Architecture

A short tour is in [`doc/architecture.md`](doc/architecture.md). In brief: the
CLI calls `DartServiceManager`, which composes a `ManifestLoader` +
`PackageResolver`, a `ServiceCompiler`, a `ServiceRegistry`, and a
`PlatformServiceDriver` — all wired over an injectable `ProcessRunner`.

## Running tests

```bash
dart test                      # unit + integration (fakes; no OS side effects)
dart test -t version           # version/pubspec sync check
dart test --coverage=coverage  # collect coverage
```

Tests tagged `os-linux` / `os-macos` / `os-windows` drive a real init system and
are skipped by default; run them explicitly on a matching host (e.g.
`dart test -t os-macos`).

## License

Licensed under the Apache License 2.0 — see [LICENSE](LICENSE).
