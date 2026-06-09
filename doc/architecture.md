# Architecture

`dart_service_manager` is a library first; the CLI is a thin wrapper over the
public API. Responsibilities are split into clean layers so the platform-specific
code is isolated and everything is testable without touching a real init system.

```text
+-----------------------+
| CLI (bin/dart_service)|   parse args -> call one API method
+-----------------------+
            |
            v
+-----------------------+
| DartServiceManager    |   orchestration only (no platform logic)
| Public API            |
+-----------------------+
   |        |        |        \
   v        v        v         v
Manifest  Compiler  Registry   Platform Abstraction
+Resolver (exe)     (JSON repo)  PlatformServiceDriver
                                    |       |       |
                                    v       v       v
                                  Linux   macOS   Windows
                                 systemd  launchd   SCM
                                    \      |       /
                                     v     v      v
                                     ProcessRunner (injectable)
```

## Layers

### CLI (`lib/src/cli`)
`buildServiceRunner` assembles an `args` `CommandRunner<int>`; each `Command`
parses its arguments and delegates to exactly one `DartServiceManager` method.
No business logic lives here. `runCli` maps `UsageException` to exit code 64 and
`ServiceManagerException` to exit code 1.

### Public API (`lib/src/manager`)
`DartServiceManager` is the single facade. It resolves a package, loads its
manifest, compiles entrypoints, drives the platform, and records results in the
registry. Every collaborator is constructor-injected; `DartServiceManager.forCurrentPlatform`
wires the production defaults.

### Manifest (`lib/src/manifest`)
- `ManifestLoader` reads the `dart_services:` section from a package's
  `pubspec.yaml` and validates it into a `ServiceManifest`.
- `PackageResolver` maps a package *name* to a directory: explicit `--path`,
  then the current directory, then `.dart_tool/package_config.json`.

### Compiler (`lib/src/compiler`)
`ServiceCompiler` runs `dart compile exe` through the `ProcessRunner`, caches the
binary under the managed binaries directory, and skips recompilation when the
output is newer than the source (unless `force` is set).

### Registry (`lib/src/registry`)
`ServiceRegistry` is a repository contract; `JsonServiceRegistry` implements it
over a single JSON file with atomic (temp-file + rename) writes and in-process
serialisation. `StoragePaths` resolves per-platform data locations. The registry
is the source of truth for *which* services this tool installed — independent of
OS discovery — while live status is always re-queried from the driver.

### Platform abstraction (`lib/src/drivers`)
`PlatformServiceDriver` is the seam between orchestration and the OS. One
implementation per init system generates the native artifact (unit file, plist)
and issues the native commands:

| Driver | Artifact | Tool | Pause/Resume |
|--------|----------|------|--------------|
| `LinuxSystemdDriver` | `.service` unit | `systemctl` | no |
| `MacOsLaunchdDriver` | `.plist` | `launchctl` | no |
| `WindowsServiceDriver` | (SCM entry) | `sc.exe` | yes |

`ServiceDriverFactory.forCurrentPlatform` selects the right one.

### Process abstraction (`lib/src/process`)
Every external command flows through `ProcessRunner`. `SystemProcessRunner` is
the production pass-through over `dart:io`; tests inject a fake that records
invocations and returns scripted results, so drivers and the compiler are fully
unit-testable.

## Cross-cutting concerns

- **Scope** — `ServiceScope { user, system }` selects per-user (no elevation) or
  machine-wide (requires root/admin) installation. Default is `user`, matching
  the per-user registry location.
- **Errors** — a `sealed` `ServiceManagerException` hierarchy with stable codes
  (`ErrorCodes`) lets callers pattern-match exhaustively and preserves root
  causes via `cause`.
- **Logging** — `ServiceLogger` with `LogLevel` is injectable; the default is
  silent, and `ConsoleServiceLogger` writes to stdout/stderr.

## Design principles

- Library-first; the CLI never implements business logic.
- Platform abstraction strictly separated from orchestration.
- Constructor dependency injection throughout; no global mutable state.
- Immutable, structurally-equal value objects with validating factories.
