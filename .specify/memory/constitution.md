# Constitution

## Core Principles

### I. Readability First

Code MUST be clean and human-readable with meaningful variable names. Descriptive
names that convey intent are required. Clarity MUST be prioritized over brevity.

**Rationale**: Readable code reduces cognitive load, speeds up onboarding, and
minimizes bugs caused by misunderstanding.

### II. Functional Design

Services MUST take inputs and yield deterministic outputs. Business logic functions
MUST NOT create side effects. Given the same inputs, functions MUST produce the
same results.

**Rationale**: Pure functions are easier to test, reason about, and compose. They
enable confident refactoring and reduce hidden dependencies.

### III. Maintainability Over Cleverness

The codebase values longevity over clever code. Premature optimizations are
prohibited. Code MUST be maintainable by future developers who did not write it.

**Rationale**: Clever code impresses once but costs repeatedly. Maintainable code
enables sustainable development velocity over the project lifetime.

### IV. Best Practices

All code MUST follow established conventions for the languages, frameworks, and
packages in use. Community standards and idioms MUST be adhered to. Proven patterns
SHOULD be leveraged over novel approaches.

**Rationale**: Best practices encode collective wisdom. Following them reduces
surprises and enables developers to apply existing knowledge.

### V. Simplicity (KISS & YAGNI)

Implementations MUST be kept simple and straightforward. Features MUST NOT be
built until needed. Simpler solutions that can be validated MUST be preferred
before investing in sophisticated alternatives.

**Rationale**: Complexity is the enemy of reliability. Simple solutions are faster
to build, easier to verify, and cheaper to change.

## Development Standards

### Spec & Branch Naming Convention

All specification directories and their corresponding Git branches MUST follow
the naming pattern:

```
XXXX-type-description
```

Where:

- `XXXX` is a 4-character alphanumeric ID derived from the last 4 characters of a UUID
- `type` is **MANDATORY** and MUST be one of: `feat` (new feature), `fix` (bug fix), or `chore` (maintenance/refactor)
- `description` is a kebab-case summary of the spec purpose

**The type segment is NEVER optional.** Omitting the type violates this convention.

**Git Branch Rule**: The Git branch name MUST exactly match the spec directory name.

### Test-First Development

Unit tests for new logic MUST be written before the implementation code. Tests MUST
be executed and verified to FAIL before implementation begins. The implementation is
then written to make the failing tests pass.

This applies to:

- New service functions and business logic
- New hooks and utilities
- Bug fixes (write a test that reproduces the bug, verify it fails, then fix)

**Rationale**: Writing tests first proves they validate the intended behavior and
prevents false-positive test suites. It drives minimal, focused implementations and
provides immediate feedback during development.

### Dev Server Verification

When implementing features that involve web UI or API changes, the development
server MUST be used for implementation verification:

1. **Pre-check**: Check whether a dev server is already running. Reuse it — do NOT
   start a duplicate.
2. **Startup**: If none is running, start it before implementation work requiring
   verification.
3. **Verification**: Implemented features MUST be verified against the running dev
   server. Unit tests alone are insufficient for UI and integration work.
4. **Cleanup**: Stop any dev server processes started during the session when
   implementation is complete.
5. **Process hygiene**: Do NOT leave straggling processes (dev servers, watchers,
   child processes) in the background.

**Rationale**: Verifying against the running application catches integration
issues that unit tests miss. Enforcing cleanup prevents resource leaks and port
conflicts.

### Process Cleanup (Mandatory)

**Every process started during a session MUST be stopped when the session ends.**
This is a hard rule with no exceptions — not for happy paths, not for error paths,
not for "I'll clean it up later."

Scope: dev servers, test watchers, Docker containers, background build processes,
file watchers, any subprocess spawned for the task.

**Docker**: any `docker run` or `docker compose up` invocation MUST be paired with
cleanup before the session completes:

```bash
docker stop <id> && docker rm <id>
# or
docker compose down
```

Never leave containers running after work is done. `docker ps` MUST be clean.

**Verification**: Before declaring work complete, confirm cleanup:

```bash
ps aux | grep <project-pattern>   # no straggling processes
docker ps                          # no running containers from this session
```

**Failure to clean up is a constitution violation** equivalent to leaving failing
tests. It degrades the environment for future sessions and causes the exact resource
leak and port conflict problems this constitution is designed to prevent.

**Rationale**: Orphaned processes accumulate silently — they waste memory, hold
ports, and cause confusing interference in future sessions. Mandatory cleanup keeps
the environment predictable and the host machine healthy.

## Quality Gates

All code changes MUST pass the following gates before merge:

- All tests MUST pass
- Linting MUST pass with zero errors
- Type checking MUST pass with zero errors (typed languages)

## Governance

This constitution supersedes ad-hoc practices and informal conventions. All
development decisions SHOULD align with the principles defined herein.

**Amendment Process**:

1. Propose amendment with documented rationale
2. Review impact on existing code and workflows
3. Update constitution with appropriate version bump:
   - MAJOR: Backward-incompatible principle changes or removals
   - MINOR: New principles or materially expanded guidance
   - PATCH: Clarifications, wording fixes, non-semantic refinements
4. Propagate changes to dependent templates and documentation

**Compliance**: All pull requests and code reviews MUST verify alignment with
constitutional principles. Violations require justification or remediation.

**Evolution**: This constitution will evolve as the project matures. Principles
may be added, refined, or deprecated based on project needs and lessons learned.

<!-- ====== PROJECT SPECIFIC ====== -->

<!-- Add project-specific standards below (language tooling, formatting, lint rules, etc.) -->