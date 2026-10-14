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
collect_change_set() { :; }
collect_prose() { :; }
assess_damage() { :; }
run_rules() { :; }
render() { [[ "$FORMAT" == text ]] && echo "No findings."; exit 0; }

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
