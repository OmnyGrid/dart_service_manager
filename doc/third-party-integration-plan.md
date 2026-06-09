# Plan: First-class 3rd-party integration (imperative service install)

> Working/design doc. Consider removing or excluding from `dart pub publish` before release.

## Context

The motivating case is the **omnyshell** CLI: it wants to install *its own already-built
binary* (`Platform.resolvedExecutable`) as a `hub` / `node` system service, passing
**per-machine** arguments (cert/key paths, node id, tokens, hub URL) and environment.

The current public facade (`DartServiceManager`) only supports a **declarative** flow:
resolve a package → load its `dart_services:` manifest → `dart compile exe` the script →
install. There is **no public way to install an existing executable with caller-supplied
args/env**. That forced omnyshell to plan an awkward workaround (persist flags to a
`~/.omnyshell/service-*.json` file and make `hub start`/`node start` read it, because the
service can only run a fixed `['hub','start']`).

**Good news from reading the code:** the lower layers already model exactly what 3rd
parties need. The gap is small and concentrated in the facade, the registry, and a few
descriptor/manifest fields — not in the drivers.

## Current architecture (grounded references)

- `DartServiceManager.install()` hardwires resolver → manifest → compiler → descriptor →
  driver → registry (`lib/src/manager/dart_service_manager.dart:106-150`). Every install
  goes through `compiler.compileService(...)`.
- **`ServiceDescriptor` is already a complete "spec":** `executablePath`, `arguments`,
  `environment`, `scope`, `description` (`lib/src/models/service_descriptor.dart:13-44`).
- **Drivers already operate purely on a descriptor with an existing executable:**
  `PlatformServiceDriver.install(ServiceDescriptor)` (`lib/src/drivers/platform_service_driver.dart:28`),
  e.g. `LinuxSystemdDriver.buildUnitFile` consumes `executablePath`/`arguments`/`environment`
  (`lib/src/drivers/linux_systemd_driver.dart:148-175`).
- **Registry does NOT persist args/env/description** — only package/service/platform/scope/
  binaryPath/installedAt/status (`lib/src/registry/registry_entry.dart:37-71`). And
  `_descriptorOf(entry)` rebuilds a *stripped* descriptor without args/env
  (`lib/src/manager/dart_service_manager.dart:274-279`). That is fine for
  start/stop/status/uninstall today (the unit file already on disk carries args/env), but it
  blocks reconfigure, full `listServices`, and any descriptor-only install.
- **Runtime policy is hardcoded in the systemd driver:** `Restart=always`, `RestartSec=5`,
  `WorkingDirectory=dirname(exe)`, and install always `enable`s at boot
  (`linux_systemd_driver.dart:148-175,71-75`). No knobs.
- `buildUnitFile` is `@visibleForTesting` — render-to-string exists internally but there is
  no public dry-run.
- Errors are a **`sealed`** hierarchy (`lib/src/errors/service_exception.dart:18`) with
  stable codes — exhaustive `switch` is a supported usage, so adding subclasses is
  source-breaking (see Compatibility).
- Manifest parsing is strict and only understands `script`/`description`/`args`/`env`
  (`lib/src/manifest/service_manifest.dart:111-138`).
- Compiler's default Dart toolchain is `Platform.resolvedExecutable`
  (`lib/src/compiler/service_compiler.dart:98`) — relevant to the self-exe helper below.

## Goals (ordered by impact)

1. **Imperative install of an existing executable** — the core unblock.
2. **Persist args/env/description (+ new policy fields) in the registry** — required so #1's
   lifecycle/listing/reconfigure work without a manifest.
3. **Configurable runtime policy on the descriptor** — workingDirectory, restart policy,
   boot-enable (autoStart), restart delay, stop timeout.
4. **Environment-file support** — keep secrets/paths out of the unit body; solves the
   system-scope `HOME` problem.
5. **Public render / dry-run.**
6. **Self-executable helper** — "install myself as a service" in one call.
7. **`reconfigure`/`update`** — change args/env without uninstall+reinstall.
8. **Round out typed errors** — `PermissionDenied`, `AlreadyInstalled`.

## Implementation

### 1. Imperative install (facade)

Add to `DartServiceManager`:

```dart
/// Installs an already-built executable as a service, bypassing package
/// resolution, manifest loading and compilation.
Future<void> installDescriptor(ServiceDescriptor descriptor, {bool startNow = false});
```

Body: `await driver.install(descriptor);` then `registry.upsert(...)` with the **full**
descriptor (needs #2); optionally `start`. No resolver/manifest/compiler involved. This is
small because `driver.install(ServiceDescriptor)` already does the work.

Keep the existing `install(packageName, ...)` untouched; internally it can converge on the
same path once it has built its descriptor (`dart_service_manager.dart:128-137`).

### 2. Persist the full descriptor in the registry

Extend `RegistryEntry` with `arguments`, `environment`, `description`, and the new policy
fields from #3. Update `toJson`/`fromJson` (all **optional** on read for back-compat) and
`copyWith` (`registry_entry.dart`). Then:

- `install()` and `installDescriptor()` store the full set.
- Rewrite `_descriptorOf(entry)` to reconstruct the **complete** descriptor
  (`dart_service_manager.dart:274-279`).
- `_toPackageServices` / `DartPackageService` can then expose args/env if desired
  (`dart_service_manager.dart:248-272`, `lib/src/models/dart_package_service.dart`).

### 3. Configurable runtime policy

Add fields to `ServiceDescriptor` (`service_descriptor.dart`) and mirror in
`ServiceInstallConfig` (`service_install_config.dart`) and `ServiceDefinition`
(`service_manifest.dart`):

- `String? workingDirectory`
- `RestartPolicy restart` (new enum: `always` | `onFailure` | `never`) — default `always`
- `Duration restartDelay` — default `5s`
- `bool autoStart` (enable at boot) — default `true`
- `Duration? stopTimeout`

Thread them through **all three drivers**, using today's hardcoded values as defaults so
existing behaviour is unchanged:

| Field | systemd | launchd | Windows SCM |
|---|---|---|---|
| restart | `Restart=` (`always`/`on-failure`/`no`) | `KeepAlive` (bool / `SuccessfulExit`) | `sc failure … reset=/actions=restart` |
| restartDelay | `RestartSec=` | `ThrottleInterval` | `sc failure … reset=` |
| workingDirectory | `WorkingDirectory=` | `WorkingDirectory` | service has no native field → set cwd via wrapper/env |
| autoStart | `enable` vs not (`linux_systemd_driver.dart:71`) | `RunAtLoad` | `sc config start= auto|demand` |
| stopTimeout | `TimeoutStopSec=` | `ExitTimeOut` | SCM stop timeout |

### 4. Environment-file support

Add `String? environmentFile` to the descriptor.

- **systemd:** emit `EnvironmentFile=<path>` instead of inlining `Environment="k=v"`
  (`linux_systemd_driver.dart:167-169`).
- **launchd:** no native env-file → document, or have the driver source it via a small
  wrapper `ExecStart`.
- **Windows:** no env-file in SCM → set per-service env or use a wrapper; document.

Expose `bool get supportsEnvironmentFile` on the driver interface so callers/CLI can adapt.
This directly fixes the omnyshell `--system` caveat: a root service reads its config path
from an env-file the installer wrote, instead of relying on the installer's `HOME`.

### 5. Public render / dry-run

Promote rendering to the driver interface: add `String render(ServiceDescriptor)` to
`PlatformServiceDriver` (`platform_service_driver.dart`) and drop `@visibleForTesting` on
the systemd impl (`linux_systemd_driver.dart:147`); add equivalents in the launchd/Windows
drivers. Add a facade `Future<String> renderDefinition(...)` and a CLI `--dry-run` that
prints the unit/plist/command without touching the system.

### 6. Self-executable helper

Add a named constructor:

```dart
ServiceDescriptor.forCurrentExecutable({
  required String packageName,
  required String serviceName,
  List<String> arguments,
  Map<String, String> environment,
  ...policy/scope...,
});
```

It resolves `Platform.resolvedExecutable`. **Nuance to handle/document:** when the caller
runs under the Dart VM (JIT) rather than an AOT binary, `resolvedExecutable` is `dart` and
the script path must be prepended to `arguments`; for AOT/`dart pub global activate` it is
the binary itself. (Compare the compiler's own use at `service_compiler.dart:98`.)

### 7. `reconfigure` / `update`

Add `Future<void> reconfigure(ServiceDescriptor descriptor)` to the facade: re-render the
unit, `daemon-reload`/reload, preserve enabled/running state, and `registry.upsert` the new
descriptor. Depends on #2 (must read prior state) and #5 (re-render).

### 8. Round out typed errors

Add `PermissionDeniedException` (map sudo/admin-required failures from the drivers' `_run`
paths, e.g. `linux_systemd_driver.dart:220-233`) and `ServiceAlreadyInstalledException`
(when `install` hits an existing registry entry without `force`). Add codes to
`ErrorCodes`. **Compatibility:** the base type is `sealed`, so new subclasses are
source-breaking for exhaustive `switch` users → ship in a minor with a CHANGELOG note, or
reuse existing types if strict non-breaking is required.

## Files to change (representative)

- `lib/src/manager/dart_service_manager.dart` — `installDescriptor`, `reconfigure`,
  `renderDefinition`; full `_descriptorOf`.
- `lib/src/models/service_descriptor.dart` — policy/workingDir/envFile fields +
  `forCurrentExecutable`.
- `lib/src/models/service_install_config.dart`, `lib/src/manifest/service_manifest.dart`,
  `lib/src/manifest/manifest_loader.dart` — mirror new fields + parse new `dart_services:`
  keys (`workingDirectory`, `restart`, `autoStart`, `envFile`, optional `executable`).
- `lib/src/registry/registry_entry.dart` — persist args/env/description/policy (optional
  JSON, back-compat).
- `lib/src/drivers/platform_service_driver.dart` — add `render(...)` and
  `supportsEnvironmentFile`.
- `lib/src/drivers/{linux_systemd,macos_launchd,windows_service}_driver.dart` — consume new
  fields; env-file; public render.
- `lib/src/errors/{service_exception,error_codes}.dart` — new exceptions/codes.
- `lib/src/cli/{commands,cli_runner}.dart` — `install --executable …`, `--dry-run`, policy
  flags.
- `README.md`, `doc/`, `CHANGELOG.md` — document the imperative API + new manifest keys.

## Backward compatibility

- All new descriptor/manifest fields are **optional**, defaulting to today's hardcoded
  values → no behaviour change for existing declarative users.
- New registry JSON keys are optional on read; old registries still load.
- New `sealed` exception subclasses are the one source-breaking risk — gate behind a minor
  release + CHANGELOG, or fold into existing types.

## Verification

- `dart analyze` clean; `dart test` green (existing suite + new).
- **Driver unit tests** (mirror `test/unit/drivers/*_driver_test.dart`): assert
  `render()`/`buildUnitFile` output (a) is byte-identical to today when new fields are unset,
  and (b) includes the right directives when set (restart policy, workingDirectory,
  EnvironmentFile, autoStart).
- **Manager/integration test** (mirror `test/integration/manager_test.dart` with the fakes in
  `test/support/`): `installDescriptor(...)` → registry holds the full descriptor →
  start/stop/status/reconfigure/uninstall all work with **no manifest and no compiler call**.
- **Manifest test** (mirror `test/unit/manifest/service_manifest_test.dart`): new keys parse;
  malformed values throw `ServiceManifestException`.
- **Manual end-to-end on macOS** (this box, launchd, user scope): build a trivial binary,
  `installDescriptor` with args + env + restart policy, `launchctl print` to confirm the
  plist, then start/stop/uninstall.
- **Dogfood:** re-derive the omnyshell `service` plan against the new API and confirm the
  `service-*.json` config-file workaround and the `--system` HOME caveat both disappear
  (omnyshell passes `ServiceDescriptor.forCurrentExecutable` with its real flags + an
  env-file).
```
