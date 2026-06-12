# one-way-doors

Baseline pack. Irreversible changes that cannot be rolled back without data loss, downtime, or significant manual effort.

---

## OWD1. Schema migration — destructive operations

Rule: Flag any DDL operation that destroys data or narrows types: DROP COLUMN, DROP TABLE, TRUNCATE, column type narrowing (e.g., VARCHAR(255) → VARCHAR(50)), adding NOT NULL constraint without a default value on a table with existing rows.

**Severity:** CRITICAL.

Signal: SQL migration files or ORM migration definitions containing destructive DDL keywords. Also check for `ALTER TABLE ... DROP`, `ALTER TABLE ... ALTER COLUMN ... TYPE` with a narrower type.

Tag `NEEDS_HUMAN` — the decision to destroy data is always a judgment call about whether downstream consumers exist.

---

## OWD2. API contract breaking changes

Rule: Flag changes to public API surfaces that remove or rename existing capabilities: removed endpoints/routes, removed or renamed required fields in request/response bodies, changed HTTP methods, tightened validation on existing fields (e.g., field was optional, now required), changed response status codes for existing flows.

**Severity:** CRITICAL.

Signal: Route/endpoint definitions that existed before the diff and are now removed or changed incompatibly. Distinguish from additive changes — new optional fields, new endpoints, and relaxed validation are NOT one-way doors.

Tag `NEEDS_HUMAN` — breaking changes may be intentional with a versioning strategy in place.

---

## OWD3. Permission model changes

Rule: Flag changes that alter who can access what: new permission checks that lock out users who previously had access, removed permission checks that broaden access beyond intended scope, role hierarchy restructuring, new mandatory auth requirements on previously public endpoints.

**Severity:** CRITICAL.

Signal: Modified middleware, decorators, or guards around route handlers; changes to role/permission tables or enums; removal of auth checks.

Tag `NEEDS_HUMAN` — access control changes require understanding the full user base and business context.

---

## OWD4. Data deletion operations

Rule: Flag hard deletes without soft-delete fallback, purge operations that remove historical data, CASCADE DELETE constraints that propagate deletions across tables, batch delete operations without confirmation guards.

**Severity:** CRITICAL.

Signal: `DELETE FROM` without a corresponding soft-delete mechanism (no `deleted_at` column, no archive table), `ON DELETE CASCADE` on new foreign keys, scheduled purge jobs.

Tag `NEEDS_HUMAN` — data loss may be intentional (GDPR compliance, storage limits) but requires explicit sign-off.

---

## OWD5. Configuration changes with no rollback path

Rule: Flag removal of environment variables that other services depend on, deletion of feature flags (vs. disabling), encryption algorithm changes without backward-compatible decryption, key rotation without a grace period for old keys, removal of backward-compatibility shims.

**Severity:** HIGH.

Signal: Deleted env var references, removed feature flag definitions, changed encryption/hashing algorithms without a migration path, removed deprecated-but-still-read config keys.

Tag `NEEDS_HUMAN` — configuration changes often have invisible downstream consumers.

---

## OWD6. Third-party API version pinning

Rule: Flag upgrades to a new major version of an external API, SDK, or service with no backward-compatibility shim. If the old version is being sunset, the upgrade is forced but still irreversible — flag it so humans confirm the migration plan covers all call sites.

**Severity:** HIGH.

Signal: Package version bumps crossing major versions (e.g., `v2.x` → `v3.x`), changed API base URLs, removed deprecated SDK method calls replaced with new patterns.

Tag `NEEDS_HUMAN` — major version upgrades may require coordinated rollout.

---

## OWD7. Index removal on large tables

Rule: Flag DROP INDEX or equivalent on tables known or likely to be large (production query-supporting indexes). Recreating indexes on large tables is expensive (locks, time, I/O) and may cause service degradation during rebuilding.

**Severity:** MEDIUM.

Signal: `DROP INDEX`, `ALTER TABLE ... DROP INDEX`, or ORM migration removing an index. Especially concerning when the index name suggests it supports a production query pattern (e.g., `idx_users_email`, `idx_orders_created_at`).

Tag `NEEDS_HUMAN` — index removal may be intentional if the query pattern changed, but the cost of re-adding is high.

---

## Confidence guidance

- 90–100: OWD1 destructive DDL (syntax is unambiguous — DROP is DROP).
- 80–90: OWD2 API breaking changes, OWD3 permission model changes (requires understanding the public surface).
- 70–80: OWD5 config changes, OWD6 version pinning, OWD7 index removal (downstream impact may be unclear).
- <70: drop unless `--strict`.

## NEEDS_HUMAN tagging

Every rule in this pack is tagged `NEEDS_HUMAN`. One-way doors are inherently judgment calls — the question is never "is this irreversible?" (it objectively is) but "is this irreversibility acceptable given the context?" Only a human with business context can answer that.
