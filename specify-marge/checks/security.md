# security

Baseline pack. OWASP essentials, framework-agnostic. Flag only issues the diff introduces on changed lines — pre-existing issues are out of scope.

---

## S1. Hardcoded secrets

Rule: No API keys, tokens, shared secrets, JWTs, private keys, passwords, or DB credentials committed in source. Use environment variables or the language's secret management.

**Severity:** CRITICAL.

Patterns to grep (on added/modified lines):
- `api[_-]?key\s*[:=]\s*["'][^"']{12,}`
- `secret\s*[:=]\s*["'][^"']{12,}`
- `password\s*[:=]\s*["'][^"']{6,}`
- `token\s*[:=]\s*["'][A-Za-z0-9._-]{20,}`
- `-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----`
- Vendor-shaped tokens: `sk_(live|test)_[A-Za-z0-9]{24,}` (Stripe), `AKIA[0-9A-Z]{16}` (AWS), `ghp_[A-Za-z0-9]{36}` (GitHub PAT), `xox[baprs]-[A-Za-z0-9-]{10,}` (Slack)

Exclude test fixtures and recorded cassettes that intentionally carry placeholder values.

---

## S2. SQL injection

Rule: No string interpolation into SQL fragments. Always use parameterized queries.

**Severity:** CRITICAL.

Bad:
```python
cursor.execute(f"SELECT * FROM users WHERE email = '{email}'")
```
Good:
```python
cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
```

---

## S3. Command injection

Rule: No shell commands constructed by interpolating user input. Use argv-style APIs.

**Severity:** CRITICAL.

Bad: `os.system(f"rm {filename}")` / `` `rm #{filename}` `` / `exec("rm " + filename)`
Good: `subprocess.run(["rm", filename])` / `system("rm", filename)` (argv form).

---

## S4. Unsafe deserialization

Rule: No `pickle.loads`, `Marshal.load`, `yaml.load` without `safe_load`, `JSON.parse` with reviver callbacks on untrusted input, `eval` / `exec` / `Function()` on user input.

**Severity:** CRITICAL.

---

## S5. Authorization bypass

Rule: A new endpoint / handler / mutation that looks up a resource by ID must scope the lookup to the current authenticated actor, or explicitly check authorization.

**Severity:** CRITICAL (mutating operations) / HIGH (read operations).

Bad:
```python
@app.get("/accounts/{id}")
def show(id): return db.accounts.find(id)    # any logged-in user sees any account
```
Good:
```python
@app.get("/accounts/{id}")
def show(id): return current_user.accounts.find(id)
```

---

## S6. Missing input validation

Rule: New endpoints that accept user input must validate shape and constraints before using the values. Flag when a new handler passes raw request input straight into a persistence / RPC / filesystem call.

**Severity:** HIGH.

---

## S7. Open redirect

Rule: `redirect(url)` where `url` comes from a request parameter without an allowlist of hosts/schemes.

**Severity:** MEDIUM.

---

## S8. Server-side request forgery (SSRF)

Rule: Outbound HTTP from a URL derived from user input must validate the host (allowlist) and scheme.

**Severity:** HIGH.

---

## S9. Cryptographic misuse

Rule:
- No MD5 / SHA-1 for security-relevant hashing (signatures, authentication, integrity). Use SHA-256+ and HMAC.
- No hardcoded IVs / nonces.
- No ECB mode for block ciphers.
- No `Math.random()` / `rand()` for security-relevant randomness — use the platform's CSPRNG.

**Severity:** HIGH.

---

## S10. Timing-sensitive comparisons

Rule: Comparing secrets (API tokens, HMACs, session IDs) with `==` leaks timing info. Use constant-time comparison.

**Severity:** MEDIUM.

---

## S11. PII in logs / error trackers

Rule: Never log or send to an error tracker values that contain: SSN, date of birth, full card number, government ID, full names + other PII together, or raw API tokens.

**Severity:** HIGH.

---

## S12. CSRF / XSRF on state-changing requests

Rule: New state-changing HTTP handlers must either use a framework-provided CSRF protection or be explicitly scoped to token-authenticated API callers.

**Severity:** HIGH.

---

## S13. Cross-site scripting (XSS)

Rule: New template interpolations or DOM writes must not emit unescaped user input. Flag `innerHTML`, `dangerouslySetInnerHTML`, `{{{ ... }}}` (Handlebars triple-stash), unescaped template literals injected into HTML.

**Severity:** HIGH.

---

## Confidence guidance

- 95–100: S1 vendor-shaped secret regex match, S2 string-interpolated SQL, S3 string-interpolated shell, S4 obvious unsafe deserialization.
- 85–95: S5 lookup-without-scope on a user-owned resource, S9 MD5/SHA-1 for auth.
- 70–85: S6 / S7 / S12 / S13 judgment calls.
- <70: drop unless `--strict`.

## NEEDS_HUMAN tagging

Tag `NEEDS_HUMAN` for findings like "this endpoint probably needs rate limiting" or "the threat model here isn't obvious". Marge won't auto-fix these.
