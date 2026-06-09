# `dart-service` CLI reference

The CLI is a thin wrapper over `DartServiceManager`. Install it globally with:

```bash
dart pub global activate dart_service_manager
```

Then invoke `dart-service <command>` (or `dart run dart_service_manager:dart_service`
from within the package).

## Service references

Most commands take a reference in one of two forms:

- `package` — targets **every** service the package declares/installed.
- `package:service` — targets exactly one service.

## Global options

| Option | Default | Description |
|--------|---------|-------------|
| `--scope <user\|system>` | `user` | Privilege scope to install under. `system` requires root/administrator. |
| `--path <dir>` | — | Explicit package directory, overriding name resolution. |
| `-v, --verbose` | off | Enable debug logging. |
| `-h, --help` | — | Print usage (also `dart-service help <command>`). |

## Commands

| Command | Description |
|---------|-------------|
| `install <package[:service]>` | Compile and install one or all services. |
| `uninstall <package[:service]>` | Stop and remove one or all services. |
| `start <package[:service]>` | Start one or all services. |
| `stop <package[:service]>` | Stop one or all services. |
| `pause <package[:service]>` | Pause (Windows only; errors elsewhere). |
| `resume <package[:service]>` | Resume a paused service (Windows only). |
| `restart <package[:service]>` | Restart one or all services. |
| `status <package[:service]>` | Show live status of one or all services. |
| `list` | List every installed service with status. |
| `packages` | List packages that have installed services. |
| `services <package>` | List a package's installed services. |

### `install` options

| Option | Description |
|--------|-------------|
| `--executable <path>` | Install a pre-built executable as a service (instead of compiling). Requires a `package:service` ref; args after `--` are passed to the service. |
| `--dry-run` | Print the rendered unit/plist/`sc` command and exit (requires `--executable`). |
| `--start-now` | Start the service immediately after installing. |
| `--force` | Replace an existing installation. |
| `--restart <always\|on-failure\|never>` | Restart policy (`--executable` installs). Default `always`. |
| `--restart-delay <seconds>` | Delay between restarts. Default `5`. |
| `--working-dir <dir>` | Service working directory. |
| `--env-file <path>` | Environment file to load (systemd only). |
| `--no-auto-start` | Do not enable the service at boot/login. |

## Examples

```bash
# Install every service declared by ./my_package (resolved from the cwd).
dart-service install my_package

# Install just one service, system-wide.
dart-service --scope system install my_package:worker

# Install from an explicit path.
dart-service install my_package --path ../packages/my_package

# Install a pre-built executable as a service, passing it args after `--`.
dart-service install myapp:hub --executable /usr/local/bin/myapp \
  --restart on-failure --env-file /etc/myapp/hub.env -- hub start

# Preview the generated definition without installing.
dart-service install myapp:hub --executable /usr/local/bin/myapp --dry-run -- hub start

# Lifecycle.
dart-service start my_package:worker
dart-service status my_package:worker
dart-service restart my_package:worker
dart-service stop my_package:worker

# Pause/resume (Windows).
dart-service pause my_package:worker
dart-service resume my_package:worker

# Inventory.
dart-service list
dart-service packages
dart-service services my_package

# Remove.
dart-service uninstall my_package:worker
dart-service uninstall my_package          # all services
```

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success. |
| `1` | A `ServiceManagerException` (printed as `error: <message>`). |
| `64` | A usage error (bad arguments / unknown command). |
