#!/usr/bin/env bash
# shellcheck disable=SC2034  # file-level: settings consumed by functions that later tasks add; remove once all rules exist
# speckit-standards.sh — deterministic standards checks over a change set:
# damage level, PR shape, plain language, lexicon.
#
#   speckit-standards.sh --base origin/main                      # Marge, /speckit-pr: the branch diff
#   speckit-standards.sh --working-tree                          # the Stop hook: uncommitted work
#   speckit-standards.sh --dir specs/1a2b-feat-x                 # Lisa: what the branch changed under a spec dir
#   speckit-standards.sh --base origin/main --body-file body.md  # the branch and a draft description
#
# Exit 0 clean or advice only, 1 a finding blocks, 2 the engine could not run.
# Config: .specify/marge/config/damage-levels.yml (required; absent = silent exit 0)
# and .specify/marge/config/lexicon.yml (absent = lexicon rules skipped).
# Rules and config format: README.md "Standards checks". Pack contract: .specify/marge/README.md.
set -uo pipefail

CONFIG_DIR=".specify/marge/config"
PACK_LABEL="baseline/standards.sh"
ALL_GROUPS="lexicon plain-language pr-shape unrated-path"
MAX_WORDS=25
MAX_COMMENT_LINES=4
SUMMARY_MAX_WORDS=150
MAX_HOOK_REASONS=8
TAB=$'\t'

MODE=""
BASE_REF=""
DIR=""
BODY_FILE=""
ONLY="$ALL_GROUPS"
BLOCKING_ONLY=0
FORMAT=text
WORK=""

usage() {
  cat >&2 <<'EOF'
usage: speckit-standards.sh (--base REF | --working-tree | --dir PATH [--base REF])
                            [--body-file FILE] [--only GROUP[,GROUP...]]
                            [--blocking-only] [--format text|marge|hook]
groups: lexicon, plain-language, pr-shape, unrated-path
EOF
  exit 2
}

fail_to_run() { echo "speckit-standards: $*" >&2; exit 2; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) [[ $# -ge 2 ]] || usage; BASE_REF="$2"; [[ -n "$MODE" ]] || MODE=base; shift 2 ;;
      --working-tree) MODE=working-tree; shift ;;
      --dir) [[ $# -ge 2 ]] || usage; DIR="${2%/}"; MODE=dir; shift 2 ;;
      --body-file) [[ $# -ge 2 ]] || usage; BODY_FILE="$2"; shift 2 ;;
      --only) [[ $# -ge 2 ]] || usage; ONLY="${2//,/ }"; shift 2 ;;
      --blocking-only) BLOCKING_ONLY=1; shift ;;
      --format) [[ $# -ge 2 ]] || usage; FORMAT="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$MODE" ]] || usage
  case "$FORMAT" in text|marge|hook) ;; *) usage ;; esac
  local group
  for group in $ONLY; do
    [[ " $ALL_GROUPS " == *" $group "* ]] || fail_to_run "unknown group: $group (choose from ${ALL_GROUPS// /, })"
  done
  [[ -z "$BODY_FILE" || -r "$BODY_FILE" ]] || fail_to_run "cannot read body file: $BODY_FILE"
}

want() { [[ " $ONLY " == *" $1 "* ]]; }

# ── Stubs replaced by later tasks ──────────────────────────────────────────
# ── YAML subset → "keypath<TAB>value" ──────────────────────────────────────
# Two-space indentation; `key: value`, `key:` with a nested block, `- item`,
# `- key: value` opening a mapping; plain, 'single', "double" or >- folded
# scalars; inline lists [a, b]; # comments. Anything else exits 2.
IFS= read -r -d '' AWK_FLATTEN <<'AWK' || true
function die(msg) { printf("%s:%d: unsupported YAML: %s\n", FILENAME, FNR, msg) > "/dev/stderr"; exit 2 }
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function joinpath(a, b) { return (a == "" ? b : a "." b) }
function unquote(s) {
  s = trim(s)
  if (s ~ /^"/) {
    if (s !~ /"[[:space:]]*(#.*)?$/) die("unterminated double quote")
    sub(/^"/, "", s); sub(/"[[:space:]]*(#.*)?$/, "", s)
    gsub(/\\"/, "\"", s); gsub(/\\\\/, "\\", s)
    return s
  }
  if (s ~ /^'/) {
    if (s !~ /'[[:space:]]*(#.*)?$/) die("unterminated single quote")
    sub(/^'/, "", s); sub(/'[[:space:]]*(#.*)?$/, "", s)
    gsub(/''/, "'", s)
    return s
  }
  sub(/[[:space:]]+#.*$/, "", s)
  return trim(s)
}
function emit_list(keypath, text,   inner, parts, k, m) {
  inner = trim(text); sub(/^\[/, "", inner); sub(/\][[:space:]]*(#.*)?$/, "", inner)
  if (trim(inner) == "") return
  m = split(inner, parts, ",")
  for (k = 1; k <= m; k++) print keypath "." (k - 1) "\t" unquote(parts[k])
}
function handle_key(text, col,   key, rest) {
  key = text; sub(/:.*$/, "", key)
  rest = text; sub(/^[^:]*:/, "", rest); rest = trim(rest)
  pend[depth] = ""
  if (rest == "") { pend[depth] = key; return }
  if (rest == ">-" || rest == ">") { folding = joinpath(path[depth], key); foldind = col; foldbuf = ""; return }
  if (rest ~ /^[|]/) die("literal block scalars are not supported")
  if (rest ~ /^\[/) { emit_list(joinpath(path[depth], key), rest); return }
  if (rest ~ /^[{&*]/) die("flow mappings, anchors and aliases are not supported")
  print joinpath(path[depth], key) "\t" unquote(rest)
}
BEGIN { depth = 0; ind[0] = 0; path[0] = ""; kind[0] = "m"; pend[0] = ""; folding = "" }
{
  line = $0
  if (line ~ /^[[:space:]]*\t/) die("tab indentation")
  if (folding != "") {
    if (line ~ /^[[:space:]]*$/) next
    n = match(line, /[^ ]/) - 1
    if (n > foldind) { foldbuf = (foldbuf == "" ? trim(line) : foldbuf " " trim(line)); next }
    print folding "\t" foldbuf; folding = ""; foldbuf = ""
  }
  if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) next
  n = match(line, /[^ ]/) - 1
  rest = substr(line, n + 1)
  if (rest ~ /^- / || rest == "-") {
    while (ind[depth] > n) depth--
    if (!(kind[depth] == "s" && ind[depth] == n)) {
      if (kind[depth] != "m" || pend[depth] == "" || ind[depth] > n) die("sequence item without a key")
      depth++; ind[depth] = n; kind[depth] = "s"; path[depth] = joinpath(path[depth-1], pend[depth-1]); pend[depth] = ""
      pend[depth-1] = ""; count[path[depth]] = 0
    }
    item = trim(substr(rest, 3))
    i = count[path[depth]]++
    itempath = path[depth] "." i
    if (item ~ /^[A-Za-z_][A-Za-z0-9_-]*:([[:space:]]|$)/) {
      depth++; ind[depth] = n + 2; kind[depth] = "m"; path[depth] = itempath; pend[depth] = ""
      handle_key(item, n + 2)
    } else if (item ~ /^\[/) {
      emit_list(itempath, item)
    } else {
      print itempath "\t" unquote(item)
    }
    next
  }
  if (rest ~ /^[A-Za-z_][A-Za-z0-9_-]*:([[:space:]]|$)/) {
    while (ind[depth] > n || (ind[depth] == n && kind[depth] == "s")) depth--
    if (kind[depth] != "m") die("key inside a sequence")
    if (ind[depth] < n) {
      if (pend[depth] == "") die("bad indentation")
      depth++; ind[depth] = n; kind[depth] = "m"; path[depth] = joinpath(path[depth-1], pend[depth-1]); pend[depth] = ""
      pend[depth-1] = ""
    } else if (ind[depth] != n) die("bad indentation")
    handle_key(rest, n)
    next
  }
  die("unrecognized line")
}
END { if (folding != "") print folding "\t" foldbuf }
AWK

yaml_flatten() { awk "$AWK_FLATTEN" "$1"; }

# cfg_get FLAT KEY → the scalar at KEY; cfg_list FLAT PREFIX → PREFIX.0, PREFIX.1, ... in order.
cfg_get() { awk -F'\t' -v k="$2" '$1 == k { print substr($0, length($1) + 2); exit }' "$1"; }
cfg_list() {
  awk -F'\t' -v p="$2" 'index($1, p ".") == 1 && substr($1, length(p) + 2) ~ /^[0-9]+$/ { print substr($0, length($1) + 2) }' "$1"
}
# ── Globs ──────────────────────────────────────────────────────────────────
# Shell globs → ERE: `**/` crosses directories, `*` and `?` stop at `/`.
# Prepended to every awk program that matches paths.
IFS= read -r -d '' AWK_GLOB <<'AWK' || true
function glob_to_ere(g,   out, c, k, n) {
  out = ""; n = length(g)
  for (k = 1; k <= n; k++) {
    c = substr(g, k, 1)
    if (c == "*") {
      if (substr(g, k, 3) == "**/") { out = out "(.*/)?"; k += 2 }
      else if (substr(g, k, 2) == "**") { out = out ".*"; k += 1 }
      else out = out "[^/]*"
    } else if (c == "?") out = out "[^/]"
    else if (c ~ /[.+(){}\[\]|^$\\]/) out = out "\\" c
    else out = out c
  }
  return "^" out "$"
}
function specificity(g,   t) { t = g; gsub(/[*?\[\]{}]/, "", t); return length(t) }
AWK

# ── Change set ─────────────────────────────────────────────────────────────
# git diff -U0 -M on stdin → "path<TAB>line<TAB>text" for every added line.
IFS= read -r -d '' AWK_DIFF_ADDED <<'AWK' || true
/^diff --git / { path = ""; inhunk = 0; next }
/^\+\+\+ / { if ($0 !~ /^\+\+\+ \/dev\/null/) path = substr($0, 7); next }
/^--- / { next }
/^@@ / { match($0, /\+[0-9]+/); cur = substr($0, RSTART + 1, RLENGTH - 1) + 0; inhunk = 1; next }
/^Binary files / { next }
/^\\ No newline/ { next }
inhunk && /^\+/ { if (path != "") print path "\t" cur "\t" substr($0, 2); cur++; next }
inhunk && /^-/ { next }
AWK

# prose | comment | none, by extension.
kind_of() {
  case "${1##*.}" in
    md|markdown|txt) echo prose ;;
    rb|rake|py|sh|bash|zsh|yml|yaml|toml|ts|tsx|js|jsx|mjs|cjs|go|rs|java|kt|swift|c|h|cc|cpp|cs|scala) echo comment ;;
    *) echo none ;;
  esac
}

comment_prefix() {
  case "${1##*.}" in
    rb|rake|py|sh|bash|zsh|yml|yaml|toml) echo '^[[:space:]]*#[[:space:]]?' ;;
    *) echo '^[[:space:]]*//[[:space:]]?' ;;
  esac
}

# A file the engine may read line by line: known kind, on disk, at most 1 MB, valid UTF-8.
readable_text() {
  [[ "$(kind_of "$1")" != none && -f "$1" ]] || return 1
  [[ $(( $(wc -c < "$1") )) -le 1000000 ]] || return 1
  iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1
}

merge_base() { git merge-base "${BASE_REF:-origin/main}" HEAD 2>/dev/null || echo HEAD; }

# Writes $WORK/files.tsv (path, status, kind) and $WORK/added.tsv (path, line, text).
collect_change_set() {
  local -a diff_args
  case "$MODE" in
    base) diff_args=("$BASE_REF...HEAD") ;;
    working-tree) diff_args=(HEAD) ;;
    dir) diff_args=("$(merge_base)" -- "$DIR") ;;
  esac
  git -c core.quotePath=false diff --name-status -M "${diff_args[@]}" > "$WORK/name-status.txt" 2>"$WORK/git-err.txt" \
    || fail_to_run "git diff failed: $(tail -n 1 "$WORK/git-err.txt")"
  : > "$WORK/files.tsv"
  local status p1 p2 path
  while IFS="$TAB" read -r status p1 p2; do
    [[ -n "$status" ]] || continue
    path="${p2:-$p1}"
    printf '%s\t%s\t%s\n' "$path" "${status:0:1}" "$(kind_of "$path")" >> "$WORK/files.tsv"
  done < "$WORK/name-status.txt"
  git -c core.quotePath=false diff -U0 -M "${diff_args[@]}" 2>/dev/null | awk "$AWK_DIFF_ADDED" > "$WORK/added.tsv"
  if [[ "$MODE" != base ]]; then
    local -a ls_args=(ls-files --others --exclude-standard)
    [[ "$MODE" == dir ]] && ls_args+=(-- "$DIR")
    git -c core.quotePath=false "${ls_args[@]}" | while IFS= read -r path; do
      printf '%s\tA\t%s\n' "$path" "$(kind_of "$path")" >> "$WORK/files.tsv"
      readable_text "$path" && awk -v p="$path" '{ print p "\t" NR "\t" $0 }' "$path" >> "$WORK/added.tsv"
    done
  fi
  return 0
}

# ── Prose: the added lines a person reads ──────────────────────────────────
# -v mode=md|comment [-v prefix=REGEX] [-v disk=FILE]; input: added lines of ONE
# file as "path<TAB>line<TAB>text"; output: "line<TAB>text". For Markdown, fence
# state comes from the whole file on disk when every added line agrees with it.
IFS= read -r -d '' AWK_PROSE <<'AWK' || true
BEGIN { FS = "\t" }
{ n++; ln[n] = $2; tx[n] = $0; sub(/^[^\t]*\t[^\t]*\t/, "", tx[n]) }
END {
  if (mode == "comment") {
    for (k = 1; k <= n; k++) if (tx[k] ~ prefix) { t = tx[k]; sub(prefix, "", t); sub(/[[:space:]]+$/, "", t); print ln[k] "\t" t }
    exit
  }
  usedisk = 0
  if (disk != "") {
    usedisk = 1; d = 0
    while ((getline line < disk) > 0) dl[++d] = line
    close(disk)
    for (k = 1; k <= n; k++) if (!(ln[k] in dl) || dl[ln[k]] != tx[k]) { usedisk = 0; break }
  }
  if (usedisk) { inside = 0; for (k = 1; k <= d; k++) { if (dl[k] ~ /^[[:space:]]*```/) { inside = !inside; fenced[k] = 1 } else if (inside) fenced[k] = 1 } }
  else { inside = 0; for (k = 1; k <= n; k++) { if (tx[k] ~ /^[[:space:]]*```/) { inside = !inside; fenced[ln[k]] = 1 } else if (inside) fenced[ln[k]] = 1 } }
  for (k = 1; k <= n; k++) if (!(ln[k] in fenced)) print ln[k] "\t" tx[k]
}
AWK

collect_prose() {
  : > "$WORK/prose.tsv"
  local path status kind disk
  while IFS="$TAB" read -r path status kind; do
    [[ "$kind" != none ]] || continue
    awk -F'\t' -v p="$path" '$1 == p' "$WORK/added.tsv" > "$WORK/one.tsv"
    [[ -s "$WORK/one.tsv" ]] || continue
    if [[ "$kind" == prose ]]; then
      disk=""; [[ -f "$path" ]] && disk="$path"
      awk -v mode=md -v disk="$disk" "$AWK_PROSE" "$WORK/one.tsv"
    else
      awk -v mode=comment -v prefix="$(comment_prefix "$path")" "$AWK_PROSE" "$WORK/one.tsv"
    fi | awk -F'\t' -v p="$path" '{ print p "\t" $0 }' >> "$WORK/prose.tsv"
  done < "$WORK/files.tsv"
  return 0
}

prose_of() { awk -F'\t' -v p="$1" '$1 == p { print $2 "\t" substr($0, length($1) + length($2) + 3) }' "$WORK/prose.tsv"; }
# ── Damage level ───────────────────────────────────────────────────────────
# -v cfg=flattened damage-levels; stdin: one changed path per line.
# Output: LEVEL name reviewer; PATH path level pattern; BY path; ASK question.
IFS= read -r -d '' _AWK_LEVEL_BODY <<'AWK' || true
BEGIN {
  FS = "\t"
  while ((getline line < cfg) > 0) {
    split(line, kv, "\t"); key = kv[1]; val = substr(line, length(key) + 2)
    if (key == "default_level") deflevel = val
    else if (key ~ /^levels\.[0-9]+\.name$/) { split(key, p, "."); lname[p[2]] = val; nlevels = (p[2] + 1 > nlevels ? p[2] + 1 : nlevels) }
    else if (key ~ /^levels\.[0-9]+\.reviewer$/) { split(key, p, "."); lrev[p[2]] = val }
    else if (key ~ /^levels\.[0-9]+\.paths\.[0-9]+$/) { split(key, p, "."); np++; pat[np] = val; plev[np] = p[2] }
    else if (key ~ /^levels\.[0-9]+\.checklist\.[0-9]+$/) { split(key, p, "."); q = p[2] "." p[4]; qtext[q] = val; qn[p[2]]++; qorder[p[2], qn[p[2]]] = q }
    else if (key ~ /^levels\.[0-9]+\.checklist\.[0-9]+\.question$/) { split(key, p, "."); q = p[2] "." p[4]; qtext[q] = val; qn[p[2]]++; qorder[p[2], qn[p[2]]] = q }
    else if (key ~ /^levels\.[0-9]+\.checklist\.[0-9]+\.paths\.[0-9]+$/) { split(key, p, "."); q = p[2] "." p[4]; qpn[q]++; qpat[q, qpn[q]] = val; np++; pat[np] = val; plev[np] = p[2] }
    else if (key ~ /^aliases\.[0-9]+\.from$/) { split(key, p, "."); afrom[p[2]] = val; na = (p[2] + 1 > na ? p[2] + 1 : na) }
    else if (key ~ /^aliases\.[0-9]+\.to$/) { split(key, p, "."); ato[p[2]] = val }
  }
  close(cfg)
  if (nlevels == 0) { print "damage-levels.yml lists no levels" > "/dev/stderr"; exit 2 }
  for (k = 1; k <= np; k++) { pere[k] = glob_to_ere(pat[k]); pspec[k] = specificity(pat[k]) }
  defidx = -1
  for (k = 0; k < nlevels; k++) if (lname[k] == deflevel) defidx = k
  if (defidx < 0) { print "damage-levels.yml: default_level \"" deflevel "\" names no level" > "/dev/stderr"; exit 2 }
}
function rank(li) { return nlevels - li }
function candidates(path, cand,   k, c) {
  c = 1; cand[1] = path
  for (k = 0; k < na; k++) if (index(path, afrom[k]) == 1) { c++; cand[c] = ato[k] substr(path, length(afrom[k]) + 1) }
  return c
}
function level_for(path,   cand, c, k, j, best, bs, br) {
  c = candidates(path, cand); best = -1; bs = -1; br = -1; WIN_PATTERN = ""
  for (j = 1; j <= c; j++) for (k = 1; k <= np; k++) if (cand[j] ~ pere[k]) {
    if (pspec[k] > bs || (pspec[k] == bs && rank(plev[k]) > br)) { bs = pspec[k]; br = rank(plev[k]); best = plev[k]; WIN_PATTERN = pat[k] }
  }
  return (best < 0 ? defidx : best)
}
{ paths[++n] = $0 }
END {
  if (nlevels == 0 || defidx < 0) exit 2
  top = -1
  for (k = 1; k <= n; k++) { lv = level_for(paths[k]); plv[k] = lv; ppat[k] = WIN_PATTERN; if (top < 0 || rank(lv) > rank(top)) top = lv }
  if (n == 0) top = nlevels - 1
  print "LEVEL\t" lname[top] "\t" lrev[top]
  for (k = 1; k <= n; k++) { print "PATH\t" paths[k] "\t" lname[plv[k]] "\t" ppat[k]; if (plv[k] == top) print "BY\t" paths[k] }
  for (k = 1; k <= qn[top]; k++) {
    q = qorder[top, k]; asked = (qpn[q] == 0)
    for (j = 1; j <= qpn[q] && !asked; j++) { re = glob_to_ere(qpat[q, j]); for (m = 1; m <= n && !asked; m++) { c = candidates(paths[m], cand); for (x = 1; x <= c; x++) if (cand[x] ~ re) asked = 1 } }
    if (asked) print "ASK\t" qtext[q]
  }
}
AWK
AWK_LEVEL="$AWK_GLOB"$'\n'"$_AWK_LEVEL_BODY"

assess_damage() {
  cut -f1 "$WORK/files.tsv" | awk -v cfg="$WORK/dl.tsv" "$AWK_LEVEL" > "$WORK/level.tsv" || fail_to_run "cannot assess the damage level (see above)"
}

# The level, what set it, the reviewer line, and the checklist, for --format text.
level_header() {
  [[ -s "$WORK/level.tsv" ]] || return 0
  local name reviewer set_by count
  name=$(awk -F'\t' '$1 == "LEVEL" { print $2; exit }' "$WORK/level.tsv")
  reviewer=$(awk -F'\t' '$1 == "LEVEL" { print $3; exit }' "$WORK/level.tsv")
  count=$(awk -F'\t' '$1 == "BY"' "$WORK/level.tsv" | wc -l | tr -d ' ')
  if [[ "$count" -eq 0 ]]; then
    set_by="nothing in this change raises it"
  else
    set_by="set by $(awk -F'\t' '$1 == "BY" { print $2 }' "$WORK/level.tsv" | head -n 3 | paste -sd, - | sed 's/,/, /g')"
    [[ "$count" -gt 3 ]] && set_by="$set_by and $((count - 3)) more"
  fi
  echo "Damage level: $name ($set_by)"
  echo "$reviewer"
  awk -F'\t' '$1 == "ASK" { print "  - " $2 }' "$WORK/level.tsv"
}
# ── Findings ───────────────────────────────────────────────────────────────
# emit BLOCK(1|0) SEV FILE LINE RULE ISSUE FIX [TAGS]
emit() {
  local block="$1" sev="$2" file="$3" line="$4" rule="$5" issue="$6" fix="$7" tags="${8:-}"
  local brank=1 srank=3
  [[ "$block" == 1 ]] && brank=0
  case "$sev" in HIGH) srank=0 ;; MEDIUM) srank=1 ;; LOW) srank=2 ;; esac
  issue="${issue//$TAB/ }"
  fix="${fix//$TAB/ }"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$brank" "$srank" "$file" "$line" "$sev" "$rule" "$issue" "$fix" "$tags" >> "$WORK/findings.tsv"
}

yaml_escape() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }
json_escape() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; printf '%s' "$s"; }

render_text() {
  level_header
  if [[ ! -s "$1" ]]; then echo "No findings."; return 0; fi
  awk -F'\t' '{ printf("%s%-6s %s:%s  %s: %s\n", ($1 == 0 ? "BLOCK " : ""), $5, $3, $4, $6, $7) }' "$1"
}

render_marge() {
  [[ -s "$1" ]] || return 0
  local _b _s file line sev rule issue fix tags
  while IFS="$TAB" read -r _b _s file line sev rule issue fix tags; do
    printf -- '- file: %s:%s\n  severity: %s\n  confidence: 95\n  pack: %s\n  rule: %s\n  issue: "%s"\n  fix: "%s"\n  tags: [%s]\n' \
      "$file" "$line" "$sev" "$PACK_LABEL" "$rule" "$(yaml_escape "$issue")" "$(yaml_escape "$fix")" "$tags"
  done < "$1"
}

render_hook() {
  grep -q "^0$TAB" "$1" || return 0
  local reasons
  reasons=$(grep "^0$TAB" "$1" | head -n "$MAX_HOOK_REASONS" | awk -F'\t' '{ printf("%s%s:%s  %s: %s", (NR > 1 ? "\n" : ""), $3, $4, $6, $7) }')
  printf '{"decision":"block","reason":"A standards check blocks this change. Fix these before finishing:\\n%s"}\n' "$(json_escape "$reasons")"
}

render() {
  sort -t "$TAB" -k1,1n -k2,2n -k3,3 -k4,4n "$WORK/findings.tsv" > "$WORK/sorted.tsv"
  local blocking=0
  grep -q "^0$TAB" "$WORK/sorted.tsv" && blocking=1
  if [[ "$BLOCKING_ONLY" == 1 ]]; then
    grep "^0$TAB" "$WORK/sorted.tsv" > "$WORK/shown.tsv" || true
  else
    cp "$WORK/sorted.tsv" "$WORK/shown.tsv"
  fi
  case "$FORMAT" in
    text) render_text "$WORK/shown.tsv" ;;
    marge) render_marge "$WORK/shown.tsv" ;;
    hook) render_hook "$WORK/shown.tsv" ;;
  esac
  exit "$blocking"
}

# ── Rules: pr-shape ────────────────────────────────────────────────────────
# Requirement ids in prose, outside inline code and URLs. Consecutive ids share
# their separator, so the loop keeps the trailing guard character for the next match.
IFS= read -r -d '' AWK_REQUIREMENT_IDS <<'AWK' || true
{
  text = $0; gsub(/`[^`]*`/, " ", text); gsub(/https?:\/\/[^[:space:]]+/, " ", text)
  rest = text
  while (match(rest, /(^|[^[:alnum:]_])(FR|NFR|SR|SC|CHK|AS|US)-?(P[0-9]+-)?[0-9]+([^[:alnum:]_]|$)/)) {
    id = substr(rest, RSTART, RLENGTH); sub(/^[^[:alnum:]_]/, "", id); sub(/[^[:alnum:]_]$/, "", id)
    if (!(id in seen)) { seen[id] = 1; print id }
    rest = substr(rest, RSTART + RLENGTH - 1)
    if (RLENGTH <= 1) break
  }
}
AWK

rule_requirement_ids() {
  [[ -n "$BODY_FILE" ]] || return 0
  local ids
  ids=$(awk "$AWK_REQUIREMENT_IDS" "$BODY_FILE" | sort -u | paste -sd, - | sed 's/,/, /g')
  [[ -n "$ids" ]] || return 0
  emit 1 HIGH PULL_REQUEST 0 requirement-id-in-body "the description leans on requirement ids: $ids" \
    "say what changes in words a reviewer can read without opening the spec; link the spec once"
}

rule_specs_mixed() {
  local spec code
  spec=$(awk -F'\t' '$1 ~ /^specs\// { print $1; exit }' "$WORK/files.tsv")
  [[ -n "$spec" ]] || return 0
  code=$(awk -F'\t' '$1 !~ /^(specs|docs)\// && $1 !~ /\.(md|markdown|txt)$/ { print $1; exit }' "$WORK/files.tsv")
  [[ -n "$code" ]] || return 0
  emit 0 MEDIUM "$spec" 0 specs-mixed-with-code "this change edits specs/ and application code together" \
    "open a separate pull request for the specs/ changes so the code can be read on its own" NEEDS_HUMAN
}

# -v cfg=flattened damage-levels; stdin: changed paths → distinct boundary names.
# A boundary glob's first wildcard segment names the boundary.
IFS= read -r -d '' _AWK_BOUNDARIES_BODY <<'AWK' || true
BEGIN {
  FS = "\t"
  while ((getline l < cfg) > 0) {
    split(l, kv, "\t")
    if (kv[1] ~ /^boundaries\.[0-9]+$/) {
      nb++; bre[nb] = glob_to_ere(kv[2]); m = split(kv[2], seg, "/"); bseg[nb] = 0
      for (k = 1; k <= m; k++) if (seg[k] ~ /[*?]/) { bseg[nb] = k; break }
    }
  }
  close(cfg)
}
{ for (b = 1; b <= nb; b++) if (bseg[b] > 0 && $0 ~ bre[b]) { split($0, ps, "/"); if (!(ps[bseg[b]] in seen)) { seen[ps[bseg[b]]] = 1; print ps[bseg[b]] } } }
AWK
AWK_BOUNDARIES="$AWK_GLOB"$'\n'"$_AWK_BOUNDARIES_BODY"

rule_many_boundaries() {
  local names count
  names=$(cut -f1 "$WORK/files.tsv" | awk -v cfg="$WORK/dl.tsv" "$AWK_BOUNDARIES" | sort)
  count=$(grep -c . <<<"$names" 2>/dev/null || true)
  [[ "${count:-0}" -ge 2 ]] || return 0
  emit 0 MEDIUM PULL_REQUEST 0 many-boundaries "touches $count boundaries: $(paste -sd, - <<<"$names" | sed 's/,/, /g')" \
    "read each boundary on its own; split the change if the work in one does not need the others" NEEDS_HUMAN
}

# A new specs/*/spec.md opens with "## Plain summary" of at most SUMMARY_MAX_WORDS words.
IFS= read -r -d '' AWK_PLAIN_SUMMARY <<'AWK' || true
BEGIN { FS = "\t" }
$1 == p { n++; ln[n] = $2; tx[n] = substr($0, length($1) + length($2) + 3) }
END {
  start = 0
  for (k = 1; k <= n; k++) if (tolower(tx[k]) ~ /^##[[:space:]]+plain summary/) { start = k; break }
  if (!start) { print "missing\t1\t0"; exit }
  words = 0
  for (k = start + 1; k <= n && tx[k] !~ /^#+[[:space:]]/; k++) {
    t = tx[k]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
    if (t != "") words += split(t, w, /[[:space:]]+/)
  }
  print (words > max ? "long" : "ok") "\t" ln[start] "\t" words
}
AWK

rule_plain_summary() {
  local path status kind verdict line words
  while IFS="$TAB" read -r path status kind; do
    [[ "$status" == A && "$path" =~ ^specs/[^/]+/spec\.md$ ]] || continue
    IFS="$TAB" read -r verdict line words < <(awk -v p="$path" -v max="$SUMMARY_MAX_WORDS" "$AWK_PLAIN_SUMMARY" "$WORK/added.tsv")
    case "$verdict" in
      missing) emit 1 HIGH "$path" 1 plain-summary-missing 'a new spec must open with a "## Plain summary" section' \
                 "add \"## Plain summary\" ($SUMMARY_MAX_WORDS words or fewer) before the first user story" ;;
      long) emit 1 HIGH "$path" "$line" plain-summary-too-long "the plain summary is $words words; the limit is $SUMMARY_MAX_WORDS" \
              "cut it to the three questions: who is this for, what changes for them, what goes wrong if it is wrong" ;;
    esac
  done < "$WORK/files.tsv"
}

# ── Rules: plain-language ──────────────────────────────────────────────────
# input: "line<TAB>text" prose lines of one file → "line<TAB>words<TAB>excerpt"
# for every sentence over `max` words. Sentences live in the paragraph, not the
# line: consecutive lines up to a blank, a heading, a list item, a table row, or a quote.
IFS= read -r -d '' AWK_SENTENCES <<'AWK' || true
BEGIN { FS = "\t" }
{ n++; ln[n] = $1; tx[n] = substr($0, length($1) + 2) }
function strip_md(t,   s) {
  gsub(/`[^`]*`/, "CODE", t)
  gsub(/https?:\/\/[^[:space:]]+/, "URL", t)
  while (match(t, /\[[^\]]*\]\([^)]*\)/)) { s = substr(t, RSTART, RLENGTH); sub(/^\[/, "", s); sub(/\]\(.*$/, "", s); t = substr(t, 1, RSTART - 1) s substr(t, RSTART + RLENGTH) }
  gsub(/<!--[^>]*-->/, "", t)
  gsub(/\*\*|__|\*|_/, "", t)
  return t
}
function flush(first, text,   rest, pos, words, w, sentence, nl, before, excerpt, parts) {
  text = strip_md(text); rest = text; pos = 0
  while (rest != "") {
    if (match(rest, /[.!?]["')]*[[:space:]]+/)) { sentence = substr(rest, 1, RSTART + RLENGTH - 1); rest = substr(rest, RSTART + RLENGTH) }
    else { sentence = rest; rest = "" }
    before = substr(text, 1, pos); nl = gsub(/\n/, "", before)
    pos += length(sentence)
    w = sentence; gsub(/\n/, " ", w); gsub(/^[[:space:]]+|[[:space:]]+$/, "", w)
    if (w == "") continue
    words = split(w, parts, /[[:space:]]+/)
    if (words > max) { excerpt = substr(w, 1, 70); gsub(/\t/, " ", excerpt); printf("%d\t%d\t%s\n", first + nl, words, excerpt) }
  }
}
END {
  first = 0; buf = ""
  for (k = 1; k <= n; k++) {
    t = tx[k]
    blank = (t ~ /^[[:space:]]*$/); blockstart = (t ~ /^[[:space:]]*(#|[-*+][[:space:]]|[0-9]+\.[[:space:]]|\||>)/)
    broken = (k > 1 && (ln[k] != ln[k-1] + 1 || blank || blockstart || tx[k-1] ~ /^[[:space:]]*#/ || tx[k-1] ~ /^[[:space:]]*$/))
    if (broken && buf != "") { flush(first, buf); buf = "" }
    if (blank) continue
    if (t ~ /^[[:space:]]*\|/) continue
    hdr = t; if (sub(/^[[:space:]]*#+[[:space:]]*/, "", hdr)) t = hdr
    lst = t; if (sub(/^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+/, "", lst)) t = lst
    if (buf == "") { first = ln[k]; buf = t } else buf = buf "\n" t
  }
  if (buf != "") flush(first, buf)
}
AWK

rule_long_sentence() {
  local path status kind line words excerpt
  while IFS="$TAB" read -r path status kind; do
    [[ "$kind" != none ]] || continue
    while IFS="$TAB" read -r line words excerpt; do
      emit 0 MEDIUM "$path" "$line" long-sentence "$words words: \"${excerpt}…\"" "split it; aim for 15 words, never more than $MAX_WORDS"
    done < <(prose_of "$path" | awk -v max="$MAX_WORDS" "$AWK_SENTENCES")
  done < "$WORK/files.tsv"
}

rule_long_comment() {
  local path status kind start run
  while IFS="$TAB" read -r path status kind; do
    [[ "$kind" == comment ]] || continue
    while IFS="$TAB" read -r start run; do
      emit 0 MEDIUM "$path" "$start" long-comment "$run lines of comment in a row" "say why in one or two sentences; link the source for the rest"
    done < <(prose_of "$path" | awk -F'\t' -v max="$MAX_COMMENT_LINES" '
      { if (n && $1 == last + 1) run++; else { if (run > max) print start "\t" run; run = 1; start = $1 } last = $1; n = 1 }
      END { if (run > max) print start "\t" run }')
  done < "$WORK/files.tsv"
}

run_rules() {
  if want pr-shape; then
    rule_requirement_ids
    rule_specs_mixed
    rule_many_boundaries
    rule_plain_summary
  fi
  if want plain-language; then
    rule_long_sentence
    rule_long_comment
  fi
}

main() {
  parse_args "$@"
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || fail_to_run "not inside a git work tree"
  cd "$root" || fail_to_run "cannot enter $root"
  [[ -f "$CONFIG_DIR/damage-levels.yml" ]] || exit 0
  WORK=$(mktemp -d) || fail_to_run "mktemp failed"
  trap 'rm -rf "$WORK"' EXIT
  yaml_flatten "$CONFIG_DIR/damage-levels.yml" > "$WORK/dl.tsv" || exit 2
  if [[ -f "$CONFIG_DIR/lexicon.yml" ]]; then
    yaml_flatten "$CONFIG_DIR/lexicon.yml" > "$WORK/lx.tsv" || exit 2
  fi
  : > "$WORK/findings.tsv"
  collect_change_set
  collect_prose
  assess_damage
  run_rules
  render
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
