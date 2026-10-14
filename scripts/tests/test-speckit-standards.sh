#!/usr/bin/env bash
# shellcheck disable=SC2034  # file-level: MODE, DIR, BASE_REF, WORK are read by the sourced engine, not here
# Tests for scripts/speckit-standards.sh. Run from anywhere:
#   bash scripts/tests/test-speckit-standards.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/../speckit-standards.sh"
FIXTURES="$HERE/fixtures/standards"
SEEDS="$HERE/../../specify-marge/config"
failures=0
TAB=$'\t'

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }
check_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got: $2, want: $3)"; fi; }
check_rc() { if [[ "$2" -eq "$3" ]]; then pass "$1"; else fail "$1 (rc=$2, want $3)"; fi; }
check_has() { if grep -qF -- "$3" <<<"$2"; then pass "$1"; else fail "$1 (missing: $3; got: ${2:0:300})"; fi; }
check_lacks() { if grep -qF -- "$3" <<<"$2"; then fail "$1 (unexpected: $3)"; else pass "$1"; fi; }

# A sandbox repo: `main` holds one commit; the work happens on branch `work`.
# $1 = which config to install: fixtures (the condensed Reset files), seeds
# (the shipped templates), or none.
make_repo() {
  sandbox=$(mktemp -d)
  cd "$sandbox" || exit 1
  git init -q -b main 2>/dev/null || { git init -q && git checkout -q -b main; }
  git config user.email test@test
  git config user.name tester
  mkdir -p .specify/marge/config
  case "$1" in
    fixtures) cp "$FIXTURES/damage-levels.yml" "$FIXTURES/lexicon.yml" .specify/marge/config/ ;;
    seeds) cp "$SEEDS/damage-levels.yml" "$SEEDS/lexicon.yml" .specify/marge/config/ ;;
  esac
  printf 'base\n' > base.txt
  git add -A
  git commit -qm init
  git checkout -qb work
}
cleanup() { cd / && rm -rf "$sandbox"; }
commit_all() { git add -A && git commit -qm "${1:-change}"; }
engine() { out=$(bash "$ENGINE" "$@" 2>"$sandbox/err.txt"); rc=$?; err=$(cat "$sandbox/err.txt"); }

# ── Task 1: CLI and silence without config ──────────────────────────────────

make_repo fixtures
engine
check_rc "no mode is a usage error" "$rc" 2
engine --base main --only bogus
check_rc "unknown --only group exits 2" "$rc" 2
check_has "unknown group is named" "$err" "bogus"
engine --base main --format xml
check_rc "unknown format exits 2" "$rc" 2
engine --base main --body-file does-not-exist.md
check_rc "missing body file exits 2" "$rc" 2
cleanup

make_repo none
printf 'x\n' > x.txt; commit_all
engine --base main
check_rc "no damage-levels.yml exits 0" "$rc" 0
check_eq "no damage-levels.yml prints nothing" "$out" ""
cleanup

make_repo fixtures
engine --base main
check_rc "clean change set exits 0" "$rc" 0
check_has "clean change set says so" "$out" "No findings."
cleanup

# ── Task 2: YAML flattener ──────────────────────────────────────────────────

# shellcheck source=../speckit-standards.sh
source "$ENGINE"

flat=$(yaml_flatten "$FIXTURES/damage-levels.yml"); rc=$?
check_rc "fixture damage-levels flattens" "$rc" 0
check_eq "fixture damage-levels line count" "$(wc -l <<<"$flat" | tr -d ' ')" "48"
check_eq "five levels" "$(grep -c '^levels\.[0-9]*\.name' <<<"$flat")" "5"
check_has "folded reviewer joined with spaces" "$flat" "levels.2.reviewer${TAB}Read all of it. This is the feature. Send it back if a sentence needs decoding."
check_has "folded question inside a sequence item" "$flat" "levels.0.checklist.2.question${TAB}Who can reach this? Can a secret, a card number or personal data end up in a log, a response or an unencrypted column?"
check_has "path-scoped question paths" "$flat" "levels.0.checklist.2.paths.1${TAB}app/models/user.rb"
check_has "plain scalar question" "$flat" "levels.0.checklist.3.question${TAB}Does this change what a member is told or agrees to?"
check_has "double-quoted glob unquoted" "$flat" "levels.3.paths.5${TAB}.*"
check_has "quoted star glob unquoted" "$flat" "levels.3.paths.6${TAB}*.yml"
check_has "comment between list items skipped" "$flat" "levels.0.checklist.2.paths.0${TAB}app/policies/**/*"
check_lacks "empty inline list emits nothing" "$flat" "levels.4.checklist"
check_has "aliases parsed" "$flat" "aliases.0.to${TAB}app/services/"

flat=$(yaml_flatten "$FIXTURES/lexicon.yml"); rc=$?
check_rc "fixture lexicon flattens" "$rc" 0
check_eq "fixture lexicon line count" "$(wc -l <<<"$flat" | tr -d ' ')" "43"
check_has "single-quoted pattern unquoted" "$flat" "banned.0.pattern${TAB}underwrit[[:alnum:]_]*"
check_has "unless list" "$flat" "prefer.0.unless.1${TAB}consumer (product|app|codebase|side|flow)"
check_has "inline list items" "$flat" "invented_phrases.nouns.7${TAB}facade"
check_has "inline list of suffixes" "$flat" "invented_phrases.compound_suffixes.3${TAB}driven"
check_eq "cfg_get reads one scalar" "$(cfg_get <(printf '%s\n' "$flat") banned.0.use)" "risk assessment"
check_eq "cfg_list reads a sequence in order" "$(cfg_list <(printf '%s\n' "$flat") known_terms | paste -sd, -)" "Jack Henry,User Story,Success Criteria,Plain Summary,Eastern Time"

tmp=$(mktemp -d)
printf 'a:\n\t- b\n' > "$tmp/tab.yml"
flat=$(yaml_flatten "$tmp/tab.yml" 2>"$tmp/err"); rc=$?
check_rc "tab indentation exits 2" "$rc" 2
check_has "tab error names the line" "$(cat "$tmp/err")" "$tmp/tab.yml:2: unsupported YAML: tab indentation"
printf 'a: &x 1\n' > "$tmp/anchor.yml"
yaml_flatten "$tmp/anchor.yml" >/dev/null 2>&1; rc=$?
check_rc "anchor exits 2" "$rc" 2
printf 'a: |\n  text\n' > "$tmp/literal.yml"
yaml_flatten "$tmp/literal.yml" >/dev/null 2>&1; rc=$?
check_rc "literal block exits 2" "$rc" 2
printf 'k: [a, "b c", d]\nq: "say \\"hi\\""\ns: '"'"'it'"'"''"'"'s'"'"'\nf: >-\n  one\n\n  two\n' > "$tmp/ok.yml"
flat=$(yaml_flatten "$tmp/ok.yml"); rc=$?
check_rc "escapes and folds parse" "$rc" 0
check_has "inline list with quoted item" "$flat" "k.1${TAB}b c"
check_has "escaped double quotes" "$flat" "q${TAB}say \"hi\""
check_has "doubled single quote" "$flat" "s${TAB}it's"
check_has "fold skips blank lines" "$flat" "f${TAB}one two"
rm -rf "$tmp"

# ── Task 3: change set and prose ────────────────────────────────────────────

# Drive the collectors directly: the engine is sourced, so set its globals.
make_repo fixtures
git checkout -q main
mkdir -p "app/services/naïve dir" docs
printf 'old\n' > "app/services/naïve dir/x.rb"
printf 'x1\nx2\nx3\nx4\nx5\nx6\nx7\nx8\nx9\nx10\n' > old.rb
printf 'Intro.\n\n```\nfenced before\n' > docs/open.md
commit_all "seed"
git checkout -q work
git merge -q main
printf 'base\nB1\nB2\n' > base.txt
git mv old.rb new.rb
printf 'x1\n# why one\n# why two\nx2\nx3\nx4\nx5\nx6\nx7\nx8\nx9\nx10\n' > new.rb
printf 'new\n' > "app/services/naïve dir/x.rb"
printf 'Intro.\n\n```\nfenced before\nadded inside fence\n```\nAfter `code` and https://x.y/z link.\n' > docs/open.md
printf '# Spec\n\nText `code` here.\n\n```sh\necho inside fence\n```\nTail.\n' > spec.md
commit_all "work"
WORK=$(mktemp -d); MODE=base; BASE_REF=main
collect_change_set
check_has "modified file listed" "$(cat "$WORK/files.tsv")" "base.txt${TAB}M${TAB}prose"
check_has "rename keeps the new path" "$(cat "$WORK/files.tsv")" "new.rb${TAB}R${TAB}comment"
check_has "unicode and space path survive" "$(cat "$WORK/files.tsv")" "app/services/naïve dir/x.rb${TAB}M${TAB}comment"
check_has "markdown is prose" "$(cat "$WORK/files.tsv")" "spec.md${TAB}A${TAB}prose"
check_has "added line numbered from the hunk" "$(cat "$WORK/added.tsv")" "base.txt${TAB}2${TAB}B1"
check_has "second added line follows" "$(cat "$WORK/added.tsv")" "base.txt${TAB}3${TAB}B2"
check_has "rename contributes only its added lines" "$(cat "$WORK/added.tsv")" "new.rb${TAB}2${TAB}# why one"
check_lacks "unchanged rename line not added" "$(cat "$WORK/added.tsv")" "new.rb${TAB}1${TAB}x1"
collect_prose
check_has "comment prefix stripped" "$(cat "$WORK/prose.tsv")" "new.rb${TAB}3${TAB}why two"
check_lacks "code line is not prose" "$(cat "$WORK/prose.tsv")" "new.rb${TAB}4"
check_has "markdown outside fences is prose" "$(cat "$WORK/prose.tsv")" "spec.md${TAB}3${TAB}Text \`code\` here."
check_lacks "fenced markdown is not prose" "$(cat "$WORK/prose.tsv")" "echo inside fence"
check_lacks "fence opened in context still fences" "$(cat "$WORK/prose.tsv")" "added inside fence"
check_has "line after the fence closes is prose" "$(cat "$WORK/prose.tsv")" "docs/open.md${TAB}7${TAB}After"
check_eq "prose_of prints one file" "$(prose_of new.rb | paste -sd'|' -)" "2${TAB}why one|3${TAB}why two"
rm -rf "$WORK"; cleanup

make_repo fixtures
printf 'untracked prose line.\n' > notes.md
printf '\x00\x01\x02' > blob.bin
printf 'base\nmore\n' > base.txt
WORK=$(mktemp -d); MODE=working-tree; BASE_REF=""
collect_change_set
check_has "working tree sees the uncommitted edit" "$(cat "$WORK/added.tsv")" "base.txt${TAB}2${TAB}more"
check_has "untracked file is added" "$(cat "$WORK/files.tsv")" "notes.md${TAB}A${TAB}prose"
check_has "untracked lines all added" "$(cat "$WORK/added.tsv")" "notes.md${TAB}1${TAB}untracked prose line."
check_has "binary untracked file keeps its path" "$(cat "$WORK/files.tsv")" "blob.bin${TAB}A${TAB}none"
check_lacks "binary untracked file carries no lines" "$(cat "$WORK/added.tsv")" "blob.bin"
rm -rf "$WORK"
mkdir -p specs/9cad-feat-x
printf '# Spec\n' > specs/9cad-feat-x/spec.md
WORK=$(mktemp -d); MODE=dir; DIR=specs/9cad-feat-x; BASE_REF=main
collect_change_set
check_has "dir mode sees the untracked spec" "$(cat "$WORK/files.tsv")" "specs/9cad-feat-x/spec.md${TAB}A${TAB}prose"
check_lacks "dir mode ignores files outside the dir" "$(cat "$WORK/files.tsv")" "base.txt"
rm -rf "$WORK"; cleanup

# ── Task 4: damage level ────────────────────────────────────────────────────

make_repo fixtures
mkdir -p app/models
printf 'class User; end\n' > app/models/user.rb
commit_all
engine --base main
check_rc "path-scoped question: exit 0 with no findings" "$rc" 0
check_has "level from an exact path" "$out" "Damage level: money and trust (set by app/models/user.rb)"
check_has "reviewer line follows" "$out" "Read every line. Work the checklist."
check_has "plain question asked" "$out" "  - What happens if this runs twice?"
check_has "path-scoped question asked when its path is touched" "$out" "  - Who can reach this?"
check_lacks "other path-scoped question not asked" "$out" "told or agrees to"
cleanup

make_repo fixtures
mkdir -p app/services/repayment_instances docs
printf 'x\n' > app/services/repayment_instances/pay.rb
printf 'y\n' > docs/a.md
commit_all
engine --base main
check_has "path-scoped question skipped when untouched" "$out" "Damage level: money and trust (set by app/services/repayment_instances/pay.rb)"
check_lacks "untouched path-scoped question" "$out" "Who can reach this?"
cleanup

make_repo fixtures
mkdir -p app/jobs/repayment_instances
printf 'x\n' > app/jobs/repayment_instances/run_job.rb
commit_all
engine --base main
check_has "alias inherits the service directory level" "$out" "Damage level: money and trust (set by app/jobs/repayment_instances/run_job.rb)"
cleanup

make_repo fixtures
mkdir -p app/services/notifications
printf 'x\n' > app/services/notifications/mailer.rb
printf 'x\n' > Gemfile
printf 'x\n' > .rubocop.yml
commit_all
engine --base main
check_has "most specific pattern wins over the catch-all" "$out" "Damage level: member-facing (set by Gemfile)"
cleanup

make_repo fixtures
mkdir -p docs
printf 'a\n' > docs/a.md; printf 'b\n' > docs/b.md; printf 'c\n' > docs/c.md; printf 'd\n' > docs/d.md
commit_all
engine --base main
check_has "more than three files are summarized" "$out" "Damage level: no runtime effect (set by docs/a.md, docs/b.md, docs/c.md and 1 more)"
check_has "a level with an empty checklist prints only its reviewer line" "$out" "Approve. Nobody is expected to read this line by line."
cleanup

make_repo fixtures
engine --base main
check_has "empty change set is the least serious level" "$out" "Damage level: no runtime effect (nothing in this change raises it)"
cleanup

make_repo fixtures
sed -i.bak 's/^default_level: member-facing/default_level: nowhere/' .specify/marge/config/damage-levels.yml && rm .specify/marge/config/damage-levels.yml.bak
engine --base main
check_rc "default_level naming no level exits 2" "$rc" 2
check_has "default_level error is explained" "$err" "default_level"
cleanup

# ── Task 5: formats and requirement-id-in-body ──────────────────────────────

make_repo fixtures
printf 'Implements FR-001 and SC-P1-003 for US2; see `FR-009` and https://x.y/FR-010 and NFR-2.\n' > body.md
engine --base main --body-file body.md
check_rc "requirement id in the body blocks" "$rc" 1
check_has "ids listed once each, sorted" "$out" "BLOCK HIGH   PULL_REQUEST:0  requirement-id-in-body: the description leans on requirement ids: FR-001, NFR-2, SC-P1-003, US2"
check_lacks "id inside inline code ignored" "$out" "FR-009"
check_lacks "id inside a URL ignored" "$out" "FR-010"
printf 'FR-001,FR-002\n' > body2.md
engine --base main --body-file body2.md
check_has "adjacent ids both found" "$out" "FR-001, FR-002"
printf 'A reviewer can read this without the spec.\n' > clean.md
engine --base main --body-file clean.md
check_rc "clean body exits 0" "$rc" 0
engine --base main --body-file body.md --format marge
check_rc "marge format still exits 1" "$rc" 1
check_has "marge file line" "$out" "- file: PULL_REQUEST:0"
check_has "marge severity" "$out" "  severity: HIGH"
check_has "marge pack label" "$out" "  pack: baseline/standards.sh"
check_has "marge rule" "$out" "  rule: requirement-id-in-body"
check_has "marge empty tags" "$out" "  tags: []"
check_has "marge quoted issue" "$out" '  issue: "the description leans on requirement ids: FR-001, NFR-2, SC-P1-003, US2"'
engine --base main --body-file clean.md --format marge
check_eq "marge prints nothing when clean" "$out" ""
engine --base main --body-file body.md --format hook
check_has "hook decision" "$out" '{"decision":"block","reason":"A standards check blocks this change. Fix these before finishing:\nPULL_REQUEST:0  requirement-id-in-body: the description leans on requirement ids: FR-001, NFR-2, SC-P1-003, US2"}'
engine --base main --body-file clean.md --format hook
check_eq "hook prints nothing when clean" "$out" ""
engine --base main --body-file body.md --only lexicon
check_rc "--only without pr-shape skips the body rule" "$rc" 0
check_has "--only without pr-shape reports clean" "$out" "No findings."
cleanup

# Escaping: a quote and a backslash inside a finding survive both formats.
make_repo fixtures
printf 'See FR-001 "quoted" and back\\slash.\n' > body.md
engine --base main --body-file body.md --format marge
check_has "marge escapes nothing in the id list" "$out" '  issue: "the description leans on requirement ids: FR-001"'
cleanup

# ── Task 6: PR shape ────────────────────────────────────────────────────────

make_repo fixtures
mkdir -p specs/9cad-feat-x app
printf '# Spec\n\n## Plain summary\n\nShort.\n' > specs/9cad-feat-x/spec.md
printf 'x\n' > app/x.rb
commit_all
engine --base main
check_rc "specs mixed with code is advice" "$rc" 0
check_has "specs mixed with code finding" "$out" "MEDIUM specs/9cad-feat-x/spec.md:0  specs-mixed-with-code: this change edits specs/ and application code together"
engine --base main --format marge
check_has "specs mixed with code needs a human" "$out" "  tags: [NEEDS_HUMAN]"
cleanup

make_repo fixtures
mkdir -p specs/9cad-feat-x docs
printf '# Spec\n\n## Plain summary\n\nShort.\n' > specs/9cad-feat-x/spec.md
printf 'notes\n' > docs/notes.md
commit_all
engine --base main
check_lacks "specs with docs only is not mixed" "$out" "specs-mixed-with-code"
cleanup

make_repo fixtures
mkdir -p app/services/reset_plaid app/jobs/reset_pave app/services/reset_x
printf 'a\n' > app/services/reset_plaid/a.rb
printf 'b\n' > app/services/reset_plaid/b.rb
printf 'j\n' > app/jobs/reset_pave/j.rb
commit_all
engine --base main
check_has "two boundaries reported once" "$out" "MEDIUM PULL_REQUEST:0  many-boundaries: touches 2 boundaries: reset_pave, reset_plaid"
cleanup

make_repo fixtures
mkdir -p app/services/reset_plaid
printf 'a\n' > app/services/reset_plaid/a.rb
commit_all
engine --base main
check_lacks "one boundary is fine" "$out" "many-boundaries"
cleanup

make_repo fixtures
mkdir -p specs/9cad-feat-x
printf '# Spec\n\n## User Scenarios\n\nText.\n' > specs/9cad-feat-x/spec.md
commit_all
engine --base main
check_rc "missing plain summary blocks" "$rc" 1
check_has "missing plain summary finding" "$out" 'BLOCK HIGH   specs/9cad-feat-x/spec.md:1  plain-summary-missing: a new spec must open with a "## Plain summary" section'
cleanup

make_repo fixtures
mkdir -p specs/9cad-feat-x
{ printf '# Spec\n\n## Plain summary\n\n'; for _ in $(seq 1 151); do printf 'word '; done; printf '\n\n## Next\n\nMore.\n'; } > specs/9cad-feat-x/spec.md
commit_all
engine --base main
check_rc "long plain summary blocks" "$rc" 1
check_has "long plain summary finding at the heading line" "$out" "BLOCK HIGH   specs/9cad-feat-x/spec.md:3  plain-summary-too-long: the plain summary is 151 words; the limit is 150"
cleanup

make_repo fixtures
mkdir -p specs/9cad-feat-x
printf '# Spec\n\n## Plain Summary *(mandatory)*\n\nWho, what, and what goes wrong.\n\n## Next\n' > specs/9cad-feat-x/spec.md
commit_all
engine --base main
check_lacks "case-insensitive heading with suffix passes" "$out" "plain-summary"
printf '# Spec\n\n## Plain Summary\n\nEdited later.\n' > specs/9cad-feat-x/spec.md
commit_all
engine --base HEAD~1
check_lacks "an existing spec is never checked for a summary" "$out" "plain-summary"
cleanup

# ── Task 7: plain language ──────────────────────────────────────────────────

make_repo fixtures
mkdir -p docs
{
  printf '# Title\n\n'
  printf 'One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six.\n\n'
  printf 'Short first. One two three four five six seven eight nine ten eleven twelve thirteen\nfourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six twenty-seven.\n\n'
  printf '```\none two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six.\n```\n\n'
  printf '| one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twenty-one twenty-two twenty-three twenty-four twenty-five twenty-six |\n\n'
  printf -- '- A list item with [a link](https://example.com/x) and `code` stays short.\n'
} > docs/long.md
commit_all
engine --base main
check_rc "long sentences are advice" "$rc" 0
check_has "26-word sentence flagged with its count" "$out" "MEDIUM docs/long.md:3  long-sentence: 26 words: \"One two three four five six seven eight nine ten eleven twelve thirtee…\""
check_has "sentence wrapped over two lines reported on its own line" "$out" "MEDIUM docs/long.md:5  long-sentence: 27 words:"
check_lacks "fenced code is not a sentence" "$out" "docs/long.md:9"
check_lacks "table row is not a sentence" "$out" "docs/long.md:12"
check_eq "exactly two long sentences" "$(grep -c 'long-sentence' <<<"$out")" "2"
engine --base main --format marge
check_has "long sentence has a fix" "$out" '  fix: "split it; aim for 15 words, never more than 25"'
cleanup

make_repo fixtures
printf 'x = 1\n# one\n# two\n# three\n# four\n# five\ny = 2\n# a\n# b\n# c\n# d\n' > code.rb
printf 'let x = 1;\n// one\n// two\n// three\n// four\n// five\n' > code.ts
commit_all
engine --base main
check_has "five hash comment lines flagged at the first" "$out" "MEDIUM code.rb:2  long-comment: 5 lines of comment in a row"
check_lacks "four comment lines are fine" "$out" "code.rb:8"
check_has "slash comments count too" "$out" "MEDIUM code.ts:2  long-comment: 5 lines of comment in a row"
cleanup

# ── Task 8: lexicon ─────────────────────────────────────────────────────────

make_repo fixtures
mkdir -p specs/9cad-feat-x docs/standards
{
  printf '# Spec\n\n## Plain summary\n\nShort.\n\n'
  printf 'Underwriting starts here. Consumers pay today.\n'
  printf 'The direct-to-consumer flow and the consumer app are fine.\n'
  printf 'We utilize the vendor-neutral seam and the dispatch surface, never the attack surface or the surface.\n'
  printf 'The Risk Engine Service runs nightly. Nightly Job runs too. User Story 3 stays known.\n'
  printf 'customers\n'
  printf 'Borrower\n'
  printf 'The `underwriting` module and https://underwriting.example are never scanned.\n'
  printf '## Underwriting Heading Words\n'
  printf '| Underwriting | table |\n'
  printf 'subcustomers and borrowership stay.\n'
} > specs/9cad-feat-x/spec.md
printf 'underwriting is allowed here\n' > docs/standards/lexicon.md
commit_all
engine --base main
check_rc "a banned word blocks" "$rc" 1
check_has "banned word with its reason" "$out" 'BLOCK HIGH   specs/9cad-feat-x/spec.md:7  lexicon-banned: "Underwriting" — say "risk assessment". Reset does not do this.'
check_has "preferred word" "$out" 'MEDIUM specs/9cad-feat-x/spec.md:7  lexicon-prefer: "Consumers" — say "member".'
check_lacks "unless suppresses the whole line" "$out" "spec.md:8  lexicon-prefer"
check_has "plain verb" "$out" 'LOW    specs/9cad-feat-x/spec.md:9  plain-verb: "utilize" — say "use".'
check_has "compound invented phrase once" "$out" 'MEDIUM specs/9cad-feat-x/spec.md:9  invented-phrase: "vendor-neutral seam" is built from generic words.'
check_eq "invented phrase reported once per line" "$(grep -c 'vendor-neutral seam' <<<"$out")" "1"
check_has "modifier plus generic noun" "$out" '"dispatch surface" is built from generic words.'
check_lacks "allowed phrase" "$out" '"attack surface"'
check_lacks "noun after an article" "$out" '"the surface"'
check_has "new Title Case term" "$out" 'LOW    specs/9cad-feat-x/spec.md:10  lexicon-new-term: "Risk Engine Service" looks like a new term.'
check_lacks "sentence-start capital drops its first word" "$out" '"Nightly Job"'
check_lacks "known term" "$out" '"User Story"'
check_has "whole-line match at line start" "$out" 'specs/9cad-feat-x/spec.md:11  lexicon-prefer: "customers" — say "member".'
check_has "whole-line match at line end" "$out" 'specs/9cad-feat-x/spec.md:12  lexicon-banned: "Borrower" — say "member".'
check_lacks "inline code and URLs are never scanned" "$out" "spec.md:13"
check_has "headings are scanned for words" "$out" 'spec.md:14  lexicon-banned: "Underwriting"'
check_lacks "headings are not new terms" "$out" '"Underwriting Heading Words"'
check_has "table cells are scanned for words" "$out" 'spec.md:15  lexicon-banned: "Underwriting"'
check_lacks "a pattern never matches inside a longer word" "$out" "spec.md:16"
check_lacks "exempt path never scanned" "$out" "docs/standards/lexicon.md"
engine --base main --format marge
check_has "new term needs a human" "$out" "  rule: lexicon-new-term"
check_has "marge escapes quotes in the issue" "$out" '  issue: "\"Underwriting\" — say \"risk assessment\". Reset does not do this."'
check_has "new term fix names the config" "$out" '  fix: "add it to known_terms in .specify/marge/config/lexicon.yml in this change, or write it in plain lower-case words"'
cleanup

make_repo fixtures
printf 'Underwriting in a comment is found too.\n' > note.txt
printf 'x\n# underwriting here\n' > code.rb
commit_all
engine --base main
check_has "txt prose scanned" "$out" "note.txt:1  lexicon-banned"
check_has "comment scanned" "$out" "code.rb:2  lexicon-banned"
rm .specify/marge/config/lexicon.yml
commit_all "drop lexicon"
engine --base HEAD~1
check_rc "without lexicon.yml nothing blocks" "$rc" 0
check_lacks "without lexicon.yml no lexicon findings" "$out" "lexicon-"
cleanup

echo
if [[ "$failures" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "$failures TEST(S) FAILED"
  exit 1
fi
