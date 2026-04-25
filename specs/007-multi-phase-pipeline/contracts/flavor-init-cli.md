# Contract: `phaser-flavor-init` Flavor-Init CLI

**Implements**: FR-031, FR-032, FR-033, FR-034.
**Binary**: `phaser/bin/phaser-flavor-init`

## Synopsis

```
phaser-flavor-init [--flavor <name>] [--force] [--yes]
phaser-flavor-init --help
phaser-flavor-init --version
```

## Arguments

| Argument | Required | Description |
|---|---|---|
| `--flavor <name>` | no | Skip auto-detection and select the named shipped flavor explicitly. Required when multiple flavors auto-match (R-015). |
| `--force` | no | Overwrite an existing `.specify/flavor.yaml` (FR-034). Refused without this flag when the file already exists. |
| `--yes` | no | Skip the confirmation prompt (FR-032). Used in non-interactive automation. |
| `--help` | no | Print usage and exit 0. |
| `--version` | no | Print version and exit 0. |

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success. `.specify/flavor.yaml` written. |
| 1 | No shipped flavor matched the project's stack (FR-033). No file written. |
| 2 | Multiple shipped flavors matched and `--flavor` was not supplied (R-015). No file written. Stderr lists matching flavors. |
| 3 | `.specify/flavor.yaml` already exists and `--force` was not supplied (FR-034). No file written. |
| 4 | Operator declined the confirmation prompt. No file written. |
| 5 | `--flavor <name>` references a flavor that is not shipped. No file written. |
| 64 | Usage error. |

## stdout

On success: a single line confirming the written file path:

```
Wrote .specify/flavor.yaml (flavor: rails-postgres-strong-migrations).
```

On exit code 1: `No shipped flavor matched this project's stack.`

On exit code 2: `Multiple shipped flavors matched: <list>. Re-run with --flavor <name>.`

On exit code 3: `.specify/flavor.yaml already exists. Re-run with --force to overwrite.`

## stderr

Auto-detection details (which flavor was suggested, which signals matched) are written to stderr as plain prose, not JSON. The flavor-init command is not part of the streaming-log surface; it is an interactive setup tool.

## Auto-Detection (FR-031)

For each shipped flavor under `phaser/flavors/<name>/`:

1. Read `flavor.yaml#stack_detection.signals`.
2. For each `required: true` signal, check whether the project satisfies it (file presence, file-contains regex match).
3. If ALL required signals match, count the flavor as a candidate.

Outcomes:

- **Exactly one candidate** → suggest that flavor; prompt for confirmation unless `--yes`; on confirmation, write `.specify/flavor.yaml` (FR-032).
- **Zero candidates** → exit 1 with `No shipped flavor matched`. (FR-033)
- **More than one candidate** → exit 2 with `Multiple shipped flavors matched: <list>`. (R-015)

## Confirmation Prompt (FR-032)

Default interactive prompt:

```
Suggested flavor: rails-postgres-strong-migrations
Matched signals:
  - file_present: Gemfile.lock
  - file_contains: Gemfile.lock pattern 'pg \\('
  - file_contains: Gemfile.lock pattern 'strong_migrations \\('

Write this flavor to .specify/flavor.yaml? [y/N]
```

Operator types `y` or `yes` (case-insensitive) to confirm; anything else → exit 4.

`--yes` skips the prompt and proceeds as though confirmed.

## Side Effects

- Reads project root for stack-detection signals.
- Writes `.specify/flavor.yaml` on success (creating the `.specify/` directory if it does not exist).
- Never modifies any other file.

## Examples

```bash
# Standard interactive run
phaser-flavor-init

# Non-interactive (CI / automation)
phaser-flavor-init --yes

# Force overwrite an existing flavor
phaser-flavor-init --force --yes

# Disambiguate when multiple flavors match
phaser-flavor-init --flavor rails-postgres-strong-migrations
```
