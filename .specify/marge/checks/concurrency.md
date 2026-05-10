# concurrency

Baseline pack. Race conditions, timing bugs, and concurrency hazards that manifest under load or in distributed systems.

---

## CC1. Check-then-act without atomicity (TOCTOU)

Rule: Flag code that reads a value, branches on it, then writes based on the read — without a lock, transaction, or compare-and-swap wrapping the entire sequence. Classic Time-Of-Check-Time-Of-Use bug.

**Severity:** CRITICAL.

Signal: A conditional (`if`, ternary, `switch`) that reads state from a shared resource (database, file, cache, shared variable), followed by a write to the same resource that assumes the read is still valid. Especially dangerous across await boundaries in async code.

Tag `NEEDS_HUMAN` — determining whether the race is exploitable requires understanding access patterns and concurrency levels.

---

## CC2. Shared mutable state across async boundaries

Rule: Flag a variable, object property, or module-level state that is written in one async handler/callback and read or written in another without synchronization (mutex, semaphore, channel, atomic operation).

**Severity:** HIGH.

Signal: Module-scoped `let` or mutable object used across multiple `async` functions, event handlers, or worker threads. Especially dangerous in Node.js where the event loop creates interleaving between `await` points.

Tag `NEEDS_HUMAN` — the scope of concurrent access depends on the runtime model and call patterns.

---

## CC3. Lock ordering inconsistency

Rule: Flag two or more code paths that acquire the same set of locks/mutexes in different orders. This creates deadlock potential when both paths execute concurrently.

**Severity:** HIGH.

Signal: Multiple lock acquisitions in a single function/method, especially when a different function acquires the same locks in a different sequence. Also applies to nested database transactions and distributed locks.

Tag `NEEDS_HUMAN` — lock ordering analysis requires understanding all possible call paths, not just the diff.

---

## CC4. Missing transaction boundaries

Rule: Flag multi-step database mutations that are not wrapped in a transaction. If any step fails, the database is left in an inconsistent state — partial writes with no rollback.

**Severity:** HIGH.

Signal: Multiple sequential INSERT/UPDATE/DELETE calls to a database without an enclosing `BEGIN`/`COMMIT` (or ORM transaction wrapper). Especially critical when the steps have referential integrity dependencies.

Tag `NEEDS_HUMAN` — some multi-step writes are intentionally non-transactional (eventual consistency, saga patterns).

---

## CC5. Cache invalidation window

Rule: Flag code that updates a data store and separately invalidates/updates a cache, leaving a time window where the cache holds stale data. The window between the write and the invalidation is a consistency gap.

**Severity:** MEDIUM.

Signal: A database write followed by a separate cache `delete`/`set` call (not atomic). Also applies to CDN purge after content update, or search index update after database mutation.

Tag `NEEDS_HUMAN` — whether the staleness window is acceptable depends on the read pattern and SLA.

---

## CC6. Pub/sub ordering assumptions

Rule: Flag code that assumes messages from a queue, event bus, or pub/sub system arrive in a specific order when the transport does not guarantee ordering. Most message queues (SQS, Kafka partitions with rebalancing, Redis pub/sub) have at-least-once semantics without strict ordering.

**Severity:** MEDIUM.

Signal: Message handlers that depend on processing order (e.g., "process create before update", "handle payment before confirmation") without explicit sequence numbers, idempotency keys, or ordering guarantees at the consumer level.

Tag `NEEDS_HUMAN` — ordering guarantees depend on the specific transport configuration and partitioning strategy.

---

## CC7. Non-atomic read-modify-write

Rule: Flag the pattern: read a counter/balance/quantity from a shared store, compute a new value in application code, write it back — without optimistic locking (version column), atomic increment (`SET x = x + 1`), or compare-and-swap.

**Severity:** HIGH.

Signal: SELECT followed by UPDATE (or GET followed by SET) where the new value depends on the read value, without a WHERE clause that checks the original value (optimistic lock) or an atomic operation. Common in balance/inventory/counter logic.

Tag `NEEDS_HUMAN` — determining the actual concurrency level and blast radius of a lost update requires production context.

---

## Confidence guidance

- 90–100: CC1 TOCTOU where the check-then-act pattern is syntactically unambiguous (read → branch → write on the same resource, no lock).
- 80–90: CC4 missing transactions (multiple DB writes with no transaction wrapper), CC7 non-atomic read-modify-write (SELECT then UPDATE pattern).
- 70–80: CC2 shared mutable state (requires understanding async access patterns), CC3 lock ordering (requires cross-function analysis), CC5 cache invalidation (staleness window may be acceptable), CC6 ordering assumptions (depends on transport config).
- <70: drop unless `--strict`.

## NEEDS_HUMAN tagging

Every rule in this pack is tagged `NEEDS_HUMAN`. Concurrency bugs are notoriously context-dependent — whether a race is exploitable depends on production traffic patterns, deployment topology, and acceptable consistency models. The goal is to flag potential hazards for human review, not to auto-fix.
