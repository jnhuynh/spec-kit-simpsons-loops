---
description: Detect the project's stack, suggest a matching shipped flavor, and write `.specify/flavor.yaml` on confirmation (one-shot opt-in command).
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Flight Check

Before doing anything else, verify that the required entry point is installed:

1. Check if `phaser/bin/phaser-flavor-init` exists and is executable (use the Bash tool: `test -x phaser/bin/phaser-flavor-init && echo "EXISTS" || echo "MISSING_OR_NOT_EXECUTABLE"`)
2. If **MISSING_OR_NOT_EXECUTABLE**, display this error and **STOP** — do not proceed with execution:

```
ERROR: Required entry point not found or not executable.

Missing: phaser/bin/phaser-flavor-init (executable)

This entry point is required to detect the project's stack and write
the flavor configuration file. Ensure the phaser/ Ruby toolkit is
installed and the entry point is executable:

  chmod +x phaser/bin/phaser-flavor-init
```

3. If **EXISTS**, proceed to the Goal section below.

## Goal

Run the one-shot flavor initialization tool that opts a project into phasing per FR-031..FR-034 and `contracts/flavor-init-cli.md`. The tool inspects the project's dependency manifests against each shipped flavor's `stack_detection.signals`, suggests the single matching flavor (or fails fast on zero/multi matches), prompts the operator for confirmation, and on confirmation writes `.specify/flavor.yaml` with the chosen flavor name.

This command is a **direct invocation** of the CLI binary. Per the contract, `phaser-flavor-init` is an interactive setup tool — not part of the streaming-log surface — so this command does NOT spawn a sub agent. The operator interacts with the CLI's confirmation prompt directly, and the CLI's stdout/stderr discipline is preserved.

## Execution Steps

### Step 1: Parse Arguments

Parse `$ARGUMENTS` for the following optional flags (per `contracts/flavor-init-cli.md`):

- **`--flavor <name>`**: Skip auto-detection and select the named shipped flavor explicitly. Required when multiple flavors auto-match (R-015).
- **`--force`**: Overwrite an existing `.specify/flavor.yaml` (FR-034). Refused without this flag when the file already exists.
- **`--yes`**: Skip the confirmation prompt (FR-032). Used in non-interactive automation.
- **`--help`**: Print usage and exit 0.
- **`--version`**: Print version and exit 0.

Pass `$ARGUMENTS` through to the CLI verbatim — do not mutate, reorder, or filter the argument list. The CLI owns the option-parsing surface.

### Step 2: Invoke the Flavor-Init CLI

Run the CLI directly via the Bash tool from the repository root:

```bash
phaser/bin/phaser-flavor-init $ARGUMENTS
init_status=$?
```

The CLI handles the entire workflow:

- Auto-detection across shipped flavors via `Phaser::FlavorInit::StackDetector` (FR-031).
- Refusal to overwrite an existing `.specify/flavor.yaml` without `--force` (FR-034, exit 3).
- Zero-match outcome (FR-033, exit 1) and multi-match outcome (R-015, exit 2).
- Confirmation prompt on stdin (FR-032), unless `--yes` is supplied; declined prompt exits 4.
- Success path writes `.specify/flavor.yaml` with `flavor: <name>` and prints the success message on stdout.

### Step 3: Interpret the Exit Code

Per `contracts/flavor-init-cli.md`:

| Exit Code | Meaning | Operator Action |
|---|---|---|
| 0 | Success — `.specify/flavor.yaml` written. | Run `/speckit.pipeline` to use the new flavor. |
| 1 | No shipped flavor matched the project's stack (FR-033). No file written. | Author a custom flavor or pick a shipped flavor explicitly with `--flavor <name>`. |
| 2 | Multiple shipped flavors matched and `--flavor` was not supplied (R-015). | Re-run with `--flavor <name>` choosing one of the listed flavors. |
| 3 | `.specify/flavor.yaml` already exists and `--force` was not supplied (FR-034). | Re-run with `--force` to overwrite, or remove the existing file first. |
| 4 | Operator declined the confirmation prompt. No file written. | Re-run when ready to opt in. |
| 5 | `--flavor <name>` references a flavor that is not shipped. | Re-run with a valid shipped flavor name. |
| 64 | Usage error (bad flag). | Re-run with a valid argument list; consult `--help`. |

Propagate the CLI's exit code as this command's exit code. Do NOT retry on any non-zero exit; every documented failure mode is operator-actionable.

### Step 4: Report Results

After the CLI returns, report:

- The exit code and its documented meaning (from the table above).
- On exit 0: the path of the written file (`.specify/flavor.yaml`) and the chosen flavor name.
- On exit 1, 2, 3, 4, or 5: the prose outcome the CLI printed on stdout (so the operator sees the actionable next step).
- On exit 64: the usage error from stderr.

Do NOT alter, summarize, or paraphrase the CLI's stdout/stderr output — pass it through verbatim so operators get the contract-pinned messages.

## Examples

- `/speckit.flavor.init` — Auto-detect the project's stack, suggest a flavor, prompt for confirmation, and write `.specify/flavor.yaml`.
- `/speckit.flavor.init --yes` — Same as above but skip the confirmation prompt (useful in automation).
- `/speckit.flavor.init --force --yes` — Overwrite an existing `.specify/flavor.yaml` without prompting.
- `/speckit.flavor.init --flavor rails-postgres-strong-migrations` — Skip auto-detection and select the named shipped flavor explicitly.
