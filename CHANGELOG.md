## 1.2.1

- Fix persistent user systemd on Linux when the process inherited an
  `XDG_RUNTIME_DIR` belonging to a *different* user (common under sudo/su or
  deploy scripts): the runtime directory is now derived from the detected uid
  (`/run/user/<uid>`) and an inherited value is honoured only when it matches,
  so `systemctl --user` no longer hits another user's bus and fails with
  `Failed to connect to bus: Permission denied`. That error is now recognised
  with an actionable hint, and a warning is emitted when a mismatched
  `XDG_RUNTIME_DIR` is overridden.

## 1.2.0

- **Persistent user-level systemd (Linux)**: user-scoped installs now
  auto-configure the per-user systemd environment so services install, enable,
  start, and survive logout/reboot. A new `UserSystemdManager`
  (`ensurePersistentUserSystemd()`) detects `systemctl`/`loginctl`, the current
  user/uid, lingering, the user D-Bus bus, and `XDG_RUNTIME_DIR`; enables
  lingering via `sudo -n loginctl enable-linger` when possible (warning with the
  manual command otherwise); and returns a detailed `UserSystemdStatus`
  (diagnostics + actionable warnings). The systemd driver runs it before
  user-scoped installs and passes a resolved `XDG_RUNTIME_DIR` to all
  `systemctl --user` calls, fixing `Failed to connect to bus: …` errors. Linux
  only, idempotent, never assumes root.

- **Scope/privilege warning**: `install` now detects a mismatch between the
  requested scope and the current privilege level — running under `sudo`/root
  with the default user scope (user services fail as root), or a system-scoped
  install without elevation — and warns with the fix, then proceeds. Backed by a
  new injectable `PrivilegeChecker` (`id -u` / `net session`).
- The CLI now shows warnings by default (info/debug still require `--verbose`).
- Added `--system` as a shorthand for `--scope system`.

## 1.1.0

First-class third-party / imperative integration.

- **Imperative install**: `DartServiceManager.installDescriptor(descriptor,
  {startNow, force})` installs an already-built executable as a service —
  bypassing package resolution, manifest loading and compilation — with
  caller-supplied arguments, environment and runtime policy.
- **`ServiceDescriptor.forCurrentExecutable(...)`**: install the currently
  running program (`Platform.resolvedExecutable`) as a service, handling the
  JIT (`dart <script>`) vs AOT-binary distinction.
- **Runtime policy** on `ServiceDescriptor`/`ServiceInstallConfig` and the
  `dart_services:` manifest: `workingDirectory`, `restart`
  (`always`/`on-failure`/`never`, new `RestartPolicy` enum), `restartDelay`,
  `autoStart`, `stopTimeout`, `environmentFile`. All default to the previous
  behaviour, so existing units/plists render unchanged.
- **Manifest `executable:`** as an alternative to `script:` — install a
  pre-built binary without compiling.
- **Environment-file support** (systemd `EnvironmentFile=`); drivers expose
  `supportsEnvironmentFile` and reject it where unsupported (launchd, Windows).
- **`render()` / `--dry-run`**: drivers can render the native definition
  (systemd unit, launchd plist, `sc` command) without touching the system;
  `DartServiceManager.renderDefinition(...)` and `install --executable
  --dry-run` expose it.
- **`reconfigure(descriptor)`**: re-apply a changed descriptor, preserving the
  running state.
- The registry now persists the full descriptor (args/env/description/policy),
  so lifecycle, listing and reconfigure work without a manifest. Registries
  written by 1.0.x still load.
- **CLI**: `install --executable <path>`, `--start-now`, `--dry-run`,
  `--restart`, `--restart-delay`, `--working-dir`, `--env-file`,
  `--no-auto-start`, `--force`.
- Windows services now configure SCM failure/restart actions to match the
  restart policy.

**Potentially breaking:** two new `sealed` exception subclasses —
`PermissionDeniedException` and `ServiceAlreadyInstalledException` — are added
to `ServiceManagerException`. Code that does an exhaustive `switch` over the
exception hierarchy must handle the new cases.

## 1.0.1

- Add a Shelf HTTP server example (`example/shelf_server`) showing a real web
  server declared as a service and managed end-to-end, with graceful
  `SIGTERM`/`SIGINT` shutdown.
- Document package-wide operations in the README: a bare `package` reference
  (no `:service`) targets every service of the package — including
  `uninstall` — and uninstalling deletes each service's cached native binary.

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
