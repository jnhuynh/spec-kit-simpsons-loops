# testing

Baseline pack. Enforces test-first discipline and coverage for code the diff changes.

---

## T1. New public function without a test

Rule: A new public function, method, or handler should be accompanied by a test that exercises it.

**Severity:** MEDIUM for library-like modules; HIGH for business logic / endpoints.

Signal: the diff adds a new `export function foo` / `def foo` / `pub fn foo` / `class Foo` in source, but no test file in the diff covers it.

Heuristic to locate tests: look for a mirror-named file — `foo.test.*`, `foo_test.*`, `test_foo.*`, `foo_spec.*`, `FooTests.*` — adjacent to the source OR under a parallel `tests/` / `spec/` / `__tests__/` directory.

---

## T2. Bug fix without a reproducing test

Rule: Commits whose message or branch name contains `fix`, `bug`, `regression`, `hotfix` should include a test that fails before the fix and passes after.

**Severity:** HIGH.

Signal: the feature branch's commit log contains bug-fix language AND no test file is modified in the diff.

---

## T3. Test-only assertion is a mock-call

Rule: A new test whose only `expect` / `assert` is that a mocked function was called (without checking behavioural output) is weak. Flag tests that don't assert any actual outcome.

**Severity:** LOW.

---

## T4. Skipped / disabled tests

Rule: New `xit`, `it.skip`, `pytest.mark.skip`, `#[ignore]`, `@Ignore` added in the diff.

**Severity:** MEDIUM if the skip has no comment explaining why; LOW otherwise.

---

## T5. Test data hygiene

Rule: Test fixtures, cassettes, and seed files must not contain real tokens, live-looking API keys, or real-person PII. Common patterns to grep on added lines in fixture directories:
- SSN-shaped: `\d{3}-\d{2}-\d{4}`
- Credit card PAN-shaped: `\d{13,19}` with a valid-length common prefix
- Real-looking emails (not ending in `@example.com`, `@test`, `@localhost`)
- Known-pattern bearer tokens / API keys

**Severity:** HIGH — fixtures in version control leak if real.

---

## T6. Flaky patterns

Rule: Tests that rely on wall-clock time (`Date.now()` / `time.time()` in an assertion), network calls to real hosts, or random numbers without a fixed seed are flaky.

**Severity:** LOW.

---

## T7. Over-broad mocks

Rule: Mocking the entire module under test defeats the test's purpose. If a new test mocks the primary module it's supposed to exercise, flag it.

**Severity:** LOW.

---

## T8. Missing failure-path coverage

Rule: New code that has error-handling branches (catch blocks, explicit error returns, validation failures) should have at least one test exercising the error path, not just the happy path.

**Severity:** MEDIUM.

Judgment call — tag `NEEDS_HUMAN` when the error path is clearly defensive-only (unreachable in normal operation).

---

## Confidence guidance

- 90–100: T2 bug-fix language + no test file changed; T5 SSN/PAN regex match on a live-looking value.
- 80–90: T1 new exported business-logic function with no adjacent test.
- 70–80: T4 / T6 / T8 judgment calls.
- <70: drop unless `--strict`.

## NEEDS_HUMAN tagging

Tag `NEEDS_HUMAN` when "which error path matters" requires domain knowledge.
