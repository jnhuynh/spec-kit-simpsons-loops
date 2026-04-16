# generic-bugs

Baseline pack. Detects common logic errors introduced by the diff, regardless of language or framework. Flag only issues on lines the diff touches.

---

## GB1. Null / undefined / nil handling

Rule: A new dereference of a value that could be null/undefined/nil/None must either have a prior check OR use a safe-navigation pattern available in the language.

**Severity:** HIGH.

Patterns to watch:
- `x.foo` where `x` was just returned from a function that can return null.
- `arr[0]` without checking `arr.length > 0`.
- Dictionary lookups: `d["key"].method()` without a prior `in` / `has` / `present` check.

---

## GB2. Off-by-one

Rule: New loop bounds, range slicing, index math, or array access must use the correct inclusive/exclusive bound. Flag `<` vs `<=` errors, `-1` vs `-1 + n`, `length - 1` vs `length`.

**Severity:** HIGH.

---

## GB3. Wrong argument order

Rule: When calling a function, ensure positional arguments are passed in the right order. Commonly swapped: `(from, to)`, `(key, value)`, `(old, new)`, `(expected, actual)`, `(x, y)`, `(width, height)`.

**Severity:** HIGH — these pass tests but produce wrong behaviour at runtime.

Signal: the function signature has semantically-paired params (two of the same type) and the call site's argument names look swapped relative to the declaration.

---

## GB4. Missing await / yield / callback

Rule: An async function call that returns a promise/future/coroutine must be awaited (or explicitly chained). A generator that must be exhausted must be iterated. A callback must be invoked.

**Severity:** HIGH.

Patterns:
- JavaScript/TypeScript: `someAsyncFn()` without `await` or `.then`, inside an `async` function.
- Python: `asyncio.create_task(...)` never awaited.
- Rust: `.await` missing on a Future.

---

## GB5. Race conditions

Rule: Concurrent writes to shared state without synchronization; check-then-act TOCTOU patterns; unprotected singletons.

**Severity:** CRITICAL.

Signal: new code that reads state, branches on it, then writes based on the read — without a lock/atomic/transaction wrapping both reads and writes.

---

## GB6. Swallowed exceptions

Rule: A new `catch` / `except` / `rescue` block that neither re-raises, logs, nor handles the error is a silent failure.

**Severity:** MEDIUM.

Bad:
```js
try { doWork(); } catch (e) {}
```
Good:
```js
try { doWork(); } catch (e) { logger.error('doWork failed', e); throw e; }
```

Exception: test teardown code that intentionally ignores cleanup failures. Flag only with lower confidence if the context is clearly a test.

---

## GB7. Resource leaks

Rule: Opened file handles, DB connections, sockets, subscriptions, or timers added in the diff must have a matching close / release / unsubscribe / clear — ideally in a `finally` / `defer` / `using` block.

**Severity:** MEDIUM.

---

## GB8. Wrong operator

Rule: `==` vs `===` (language-dependent), `=` vs `==`, bitwise `&` vs logical `&&`, integer vs float division.

**Severity:** MEDIUM. Usually caught by linters; flag only if the linter is unlikely to catch it (e.g. the repo doesn't run a linter for the changed file type).

---

## GB9. Dead branches

Rule: New `if (false)`, `if (true)`, unreachable code after an unconditional `return` / `throw`.

**Severity:** LOW. Usually unintentional leftover from development.

---

## GB10. Incorrect error propagation

Rule: A function that calls another fallible function must either handle the error or propagate it. Silently returning a default on error (other than intentional design) hides bugs.

**Severity:** MEDIUM.

---

## Confidence guidance

- 90–100: GB3 wrong-order with matching types, GB4 un-awaited async call, GB5 clear TOCTOU pattern.
- 80–90: GB1 / GB2 / GB6 where the pattern is unambiguous.
- 70–80: GB7 / GB10 judgment calls.
- <70: drop unless `--strict`.

## NEEDS_HUMAN tagging

Tag `NEEDS_HUMAN` when the finding requires architectural or domain judgment Marge can't reliably make — e.g. "is this race condition actually reachable in production?". Marge's loop skips NEEDS_HUMAN findings.
