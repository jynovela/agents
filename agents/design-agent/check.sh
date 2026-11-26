#!/usr/bin/env bash
# Deterministic checks for a Design-Agent run. Run from the repo root after the
# agent finishes.
#
# Usage: .agents/skills/design-agent/check.sh report.md
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# Secret values are never printed.

set -uo pipefail
. "$(dirname "$0")/../../shared/lib.sh"

report="${1:-}"
if [ -z "$report" ]; then
  echo "Usage: $0 report.md"
  exit 2
fi

# <!-- TAILOR: match "Design writes to" in AGENTS.md. -->
DESIGN="${DESIGN_DIR:-design}"
SCREENS="$DESIGN/screens"
MAPS="$DESIGN/flows"
WIRES="$DESIGN/wireframes"

esc() { printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'; }

# Design-Agent may change only files under design/ (not system.md) and its report.
check_scope "^$(esc "$DESIGN")/|^$(esc "$(basename "$report")")\$"
if changed_files | grep -qx "$DESIGN/system.md"; then
  say_fail "$DESIGN/system.md changed. Design-Agent reads the design system; it never edits it."
fi
check_secrets
check_headings "$report" "Flow:" "Actor:" "Goal:" "Entry:" "Exit:" "Needs your answer:" \
  "Existing UI:" "Flow map:" "Screens written:" "Test accounts needed:" "Ask first:" \
  "Security flags:" "Verify:"
[ -f "$report" ] || finish "Design-Agent"

section() { awk -v h="$1" '$0 ~ "^"h {f=1; next} /^[A-Z][A-Za-z ()]*:/ {f=0} f' "$report"; }
items() { section "$1" | grep -E '^ *- ' | grep -viE '^ *- *None' || true; }

# The spec file for screen id $1 (like S3), or nothing.
spec_for() { ls "$SCREENS/$1-"*.md 2>/dev/null | head -1; }

echo "== Flow and flow map"
flow="$(grep -E '^Flow:' "$report" | head -1 | sed -E 's/^Flow: *//; s/[`*]//g; s/ +$//')"
name="$(basename "$flow" .md)"
map="$MAPS/$name.md"
if [ -z "$flow" ] || [ ! -f "$flow" ]; then
  say_fail "\"Flow:\" must name the flow file; found \"$flow\""
else
  [ -z "$(git status --porcelain -- "$flow")" ] || say_fail "$flow changed. Never edit the flow."
  steps="$(grep -oE '^- F[0-9]+:' "$flow" | sed -E 's/^- (F[0-9]+):/\1/')"
  [ -n "$steps" ] || say_fail "$flow has no steps written as \"- F<n>:\""
  if [ ! -f "$map" ]; then
    say_fail "flow map $map not found"
  else
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      sid="$(grep -E "^- $f: *S[0-9]+" "$map" | head -1 | sed -E "s/^- $f: *(S[0-9]+).*/\1/")"
      if [ -z "$sid" ]; then
        say_fail "step $f has no screen in $map (write \"- $f: S<n> <name>\")"
      elif [ -z "$(spec_for "$sid")" ]; then
        say_fail "step $f uses $sid, but there's no $SCREENS/$sid-<name>.md"
      fi
    done <<< "$steps"
    echo "$(printf '%s\n' "$steps" | grep -c . | tr -d ' ') step(s) checked against $map."
  fi
fi

echo "== Screen ids are unique"
dups="$(ls "$SCREENS" 2>/dev/null | sed -nE 's/^(S[0-9]+)-.*\.md$/\1/p' | sort | uniq -d)"
for d in $dups; do say_fail "two specs use $d: $(ls "$SCREENS/$d-"*.md | tr '\n' ' ')"; done
[ -z "$dups" ] && echo "No duplicates."

echo "== New screens take the next free ids"
old_max="$(git ls-files "$SCREENS" | sed -nE 's|.*/S([0-9]+)-.*\.md$|\1|p' | sort -n | tail -1)"
old_max="${old_max:-0}"
new_ids="$(git ls-files --others --exclude-standard "$SCREENS" | sed -nE 's|.*/S([0-9]+)-.*\.md$|\1|p' | sort -n)"
want=$((old_max + 1))
for n in $new_ids; do
  [ "$n" -eq "$want" ] || say_fail "new screen S$n should be S$want: new screens take the next free ids after S$old_max, in order"
  want=$((want + 1))
done
echo "Done."

echo "== Specs"
specs="$(changed_files | grep -E "^$(esc "$SCREENS")/S[0-9]+-.*\.md$" || true)"
written="$(section 'Screens written:')"
for spec in $specs; do
  [ -f "$spec" ] || { say_fail "$spec was deleted. Never remove a screen spec."; continue; }
  sid="$(basename "$spec" | sed -E 's/^(S[0-9]+)-.*/\1/')"
  for h in Purpose "Reached from" Content Actions States Copy Accessibility "Open questions"; do
    grep -qx "## $h" "$spec" || say_fail "$spec is missing the heading \"## $h\""
  done
  extra="$(grep -E '^## ' "$spec" | grep -vxE '## (Purpose|Reached from|Content|Actions|States|Copy|Accessibility|Open questions)' || true)"
  [ -z "$extra" ] || say_fail "$spec has a heading the spec format doesn't: $(echo "$extra" | head -1). Add to the existing sections instead."
  states="$(awk '/^## States/ {f=1; next} /^## / {f=0} f' "$spec")"
  for st in Empty Loading Error Success; do
    line="$(printf '%s\n' "$states" | grep -E "^- $st:" | head -1)"
    val="$(printf '%s\n' "$line" | sed -E "s/^- $st: *//")"
    if [ -z "$line" ] || [ -z "$val" ]; then
      say_fail "$spec: state \"- $st:\" is missing or empty"
    elif printf '%s\n' "$val" | grep -qi '^not applicable'; then
      [ "${#val}" -ge 24 ] || say_fail "$spec: \"$st: Not applicable\" needs a reason"
    elif ! git ls-files --error-unmatch "$spec" >/dev/null 2>&1; then
      shown="$(printf '%s\n' "$val" | sed -nE 's/.*Shown by: *(.*)$/\1/p')"
      if [ -z "$shown" ]; then
        say_fail "$spec: state \"$st\" doesn't end with \"Shown by: <test account | simulate value | new: ...>\""
      elif printf '%s\n' "$shown" | grep -q '^?simulate='; then
        sim="$(grep -E '^- Simulate switch:' AGENTS.md 2>/dev/null | head -1)"
        printf '%s\n' "$sim" | grep -qiE ':\s*None\s*$|^$' \
          && say_fail "$spec: state \"$st\" uses $shown, but AGENTS.md has no simulate switch; use \"new:\""
      elif printf '%s\n' "$shown" | grep -q '^new:'; then
        acct="$(printf '%s\n' "$shown" | sed -E 's/^new: *//')"
        section 'Test accounts needed:' | grep -qF -- "$acct" \
          || say_fail "$spec: new test account \"${acct:0:40}\" isn't under \"Test accounts needed:\""
      else
        acct_file="$(grep -E '^- Test accounts:' AGENTS.md 2>/dev/null | head -1 | sed -nE 's/.*`([^`]+)`.*/\1/p')"
        acct_name="$(printf '%s\n' "$shown" | awk '{print $1}' | sed 's/[.,;]$//')"
        if [ -z "$acct_file" ] || [ ! -f "$acct_file" ]; then
          say_fail "$spec: state \"$st\" names test account \"$acct_name\", but AGENTS.md lists no test accounts file; use \"new:\""
        elif ! grep -qE -- "(^|[^A-Za-z0-9_.-])$(esc "$acct_name")([^A-Za-z0-9_-]|$)" "$acct_file"; then
          say_fail "$spec: test account \"$acct_name\" isn't in $acct_file; use \"new: <what it needs>\""
        fi
      fi
    fi
  done
  actions="$(awk '/^## Actions/ {f=1; next} /^## / {f=0} f' "$spec" | grep -E '^- ' || true)"
  prim="$(printf '%s\n' "$actions" | grep -c '^- Primary:' || true)"
  [ "$prim" -eq 1 ] || say_fail "$spec has $prim actions starting with \"Primary:\"; it needs exactly one"
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    case "$a" in
      *"-> S"[0-9]*)
        t="$(printf '%s\n' "$a" | sed -nE 's/.*-> (S[0-9]+).*/\1/p')"
        [ -n "$(spec_for "$t")" ] || say_fail "$spec: action points to $t, which has no spec" ;;
      *"-> back"*|*"-> system:"*) ;;
      *) say_fail "$spec: action must end in \"-> S<n>\", \"-> back\", or \"-> system: ...\": ${a:0:60}" ;;
    esac
  done <<< "$actions"
  printf '%s\n' "$written" | grep -qE -- "^ *- *$sid( |:)" || say_fail "$sid changed but isn't under \"Screens written:\""
  if git ls-files --error-unmatch "$spec" >/dev/null 2>&1; then
    removed="$(git diff HEAD -- "$spec" | grep -E '^-' | grep -vE '^--- (a/|/dev/null)' | grep -vE '^- *- *None *$' | grep -vE '^-Flows:' || true)"
    [ -z "$removed" ] || say_fail "$spec existed and lost or changed lines. Only add to an existing spec; list other changes under \"Ask first\"."
  fi
  if [ -f "$WIRES/$sid.html" ]; then
    for t in $(printf '%s\n' "$actions" | sed -nE 's/.*-> (S[0-9]+).*/\1/p' | sort -u); do
      grep -q "href=\"$t.html\"" "$WIRES/$sid.html" || say_fail "$WIRES/$sid.html has no link to $t.html, but $sid's spec has an action -> $t"
    done
  else
    say_fail "$sid has no wireframe $WIRES/$sid.html"
  fi
  echo "  OK  $spec"
done
[ -n "$specs" ] || echo "No spec changed."

echo "== Flow maps"
for m in $(changed_files | grep -E "^$(esc "$MAPS")/.*\.md$" || true); do
  if git ls-files --error-unmatch "$m" >/dev/null 2>&1; then
    removed="$(git diff HEAD -- "$m" | grep -E '^-' | grep -vE '^--- (a/|/dev/null)' || true)"
    [ -z "$removed" ] || say_fail "$m existed and lost or changed lines. Only add to it."
  fi
done
echo "Done."

echo "== Wireframes"
[ -z "${name:-}" ] || [ -f "$WIRES/$name.html" ] || say_fail "flow start page $WIRES/$name.html not found"
[ -f "$WIRES/style.css" ] || say_fail "$WIRES/style.css not found (copy .agents/skills/design-agent/tools/wireframe.css)"
for w in $(changed_files | grep -E "^$(esc "$WIRES")/.*\.html$" || true); do
  [ -f "$w" ] || continue
  if git ls-files --error-unmatch "$w" >/dev/null 2>&1; then
    removed="$(git diff HEAD -- "$w" | grep -E '^-' | grep -vE '^--- (a/|/dev/null)' || true)"
    [ -z "$removed" ] || say_fail "$w existed and lost or changed lines. Only add links and content to an existing wireframe."
  fi
  if grep -nEi '(src|href) *= *"(https?:)?//' "$w" >/dev/null; then
    say_fail "$w loads something from the internet: $(grep -nEi '(src|href) *= *"(https?:)?//' "$w" | head -1 | cut -d: -f1 | sed 's/^/line /')"
  fi
  grep -qiE '<script' "$w" && say_fail "$w has a script. Wireframes are plain HTML."
  if grep -nEi '<input[^>]*checked' "$w" >/dev/null; then
    say_fail "$w line $(grep -nEi '<input[^>]*checked' "$w" | head -1 | cut -d: -f1) has a pre-checked box. Leave it unchecked and ask under \"Needs your answer\"."
  fi
  wid="$(basename "$w" .html)"
  wspec="$(spec_for "$wid")"
  if [ -n "$wspec" ]; then
    wact="$(awk '/^## Actions/ {f=1; next} /^## / {f=0} f' "$wspec" | grep -E '^- ' || true)"
    for t in $(grep -oE 'href="S[0-9]+\.html"' "$w" | sed -E 's/href="(S[0-9]+)\.html"/\1/' | sort -u); do
      printf '%s\n' "$wact" | grep -qE -- "-> $t([^0-9]|$)" || say_fail "$w links to $t.html, but $wspec has no action -> $t. Add the action under \"## Actions\"."
    done
  fi
  for href in $(grep -oE 'href="[^"#]+' "$w" | sed 's/^href="//'); do
    case "$href" in mailto:*|tel:*|http:*|https:*|//*) continue ;; esac
    [ -e "$(dirname "$w")/$href" ] || say_fail "$w links to $href, which doesn't exist"
  done
  echo "  OK  $w"
done

echo "== Existing UI lines are real"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  loc="$(printf '%s\n' "$line" | sed -nE 's/^ *- *`?([^`: ]+):([0-9]+):.*/\1 \2/p')"
  if [ -z "$loc" ]; then
    say_fail "existing UI line must be \"- <file>:<line>: <name>: <use>\": ${line:0:50}"
    continue
  fi
  set -- $loc
  if [ ! -f "$1" ]; then
    say_fail "existing UI points to $1, which doesn't exist"
  elif [ "$2" -gt "$(wc -l < "$1")" ]; then
    say_fail "existing UI points to $1 line $2, past the end of the file"
  fi
done <<< "$(items 'Existing UI:')"
echo "Done."

echo "== Report lists use \"- \" bullets"
numbered="$(grep -nE '^ *[0-9]+[.)] ' "$report" | head -1 | cut -d: -f1)"
[ -z "$numbered" ] || say_fail "$report line $numbered is a numbered item. Write every item as \"- ...\"."
echo "Done."

echo "== Ask first"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  say_fail "\"Ask first\" repeats a question: ${line:0:50}. List only screens or changes you didn't design."
done <<< "$(items 'Ask first:' | grep -iE '^ *- *Q[0-9]+|dark pattern|no exit|exit is missing' || true)"
if [ -n "${flow:-}" ] && [ -f "$flow" ]; then
  notes="$(awk '/^## Notes/ {f=1; next} /^## / {f=0} f' "$flow" | grep -E '^- ' || true)"
  if [ -n "$notes" ] && [ -z "$(items 'Ask first:')" ]; then
    say_fail "$flow has notes under \"## Notes\", but \"Ask first\" is empty. List each screen or feature a note mentions."
  fi
fi
echo "Done."

echo "== Security flags"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  say_fail "\"Security flags\" lists a dark pattern: ${line:0:50}. Dark patterns go under \"Needs your answer\" only."
done <<< "$(items 'Security flags:' | grep -iE 'dark pattern|pre-?checked|already checked' || true)"
echo "Done."

echo "== Reused screens are under \"Existing UI\""
if [ -f "${map:-}" ]; then
  for sid in $(sed -nE 's/^- F[0-9]+: *(S[0-9]+).*/\1/p' "$map" | sort -u); do
    sp="$(spec_for "$sid")"
    [ -n "$sp" ] && git ls-files --error-unmatch "$sp" >/dev/null 2>&1 || continue
    items 'Existing UI:' | grep -qF -- "$sp:" || say_fail "the flow reuses $sid, but \"Existing UI\" doesn't list $sp. Write \"- $sp:1: $sid <name>: reused for F<n>\"."
  done
fi
echo "Done."

echo "== Gaps stay undesigned"
newspecs="$(git ls-files --others --exclude-standard "$SCREENS" | grep -E '\.md$' || true)"
if grep -qE '^Exit: *missing' "$report" && [ -n "$newspecs" ]; then
  cat $newspecs | grep -qE -- '-> system: *see Q[0-9]+' \
    || say_fail "Exit is missing, so the last step's action must be \"-> system: see Q<n>\", not a screen you chose"
fi
for sp in $newspecs; do
  if grep -qi 'legal' "$sp" && ! grep -q '\[Legal:' "$sp"; then
    say_fail "$sp mentions legal text without a placeholder like \"[Legal: <what>, from the legal team]\". Don't write legal text yourself."
  fi
done
echo "Done."

echo "== Needs your answer"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  echo "$line" | grep -Eq '^ *- *Q[0-9]+ *\|.*\| *gap:.*\| *proposed:' \
    || say_fail "needs-your-answer line must be \"- Q<n> | <where> | gap: ... | proposed: ...\": ${line:0:60}"
done <<< "$(items 'Needs your answer:')"
if grep -qE '^Exit: *missing' "$report" && ! items 'Needs your answer:' | grep -qi 'exit'; then
  say_fail "Exit is missing, but no \"Needs your answer\" line asks about the exit"
fi
acct_file="$(grep -E '^- Test accounts:' AGENTS.md 2>/dev/null | head -1 | sed -nE 's/.*`([^`]+)`.*/\1/p')"
if [ -n "$acct_file" ] && [ -f "$acct_file" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    a="$(printf '%s\n' "$line" | sed -E 's/^ *- *`?([^`:]+)`?:.*/\1/')"
    grep -qF -- "\`$a\`" "$acct_file" && say_fail "\"Test accounts needed\" lists $a, which already exists in $acct_file. List only new accounts."
  done <<< "$(items 'Test accounts needed:')"
fi
echo "Done."

finish "Design-Agent"
