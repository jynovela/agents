#!/usr/bin/env bash
# Deterministic checks for a Planner-Agent run. Run from the repo root after
# the agent writes its drafts, and before anything is created in Linear.
#
# Usage: .agents/checks/planner-agent.sh [report-file] [created]
#   report-file: the agent's report. When given, the script also checks its
#   headings and that it matches the drafts.
#   created: Linear mode only. Run again after the tickets are created, to
#   check that "Created:" maps every draft to a Linear ID.
#
# Exit code 0 means all checks passed. Any failure prints FAIL and exits 1.
# Written for bash 3.2 and BSD tools, so it runs on a stock Mac.

set -uo pipefail
. "$(dirname "$0")/lib.sh"

# TAILOR: where drafts go, and the files the Planner-Agent may change.
DRAFTS_DIR='.tickets/drafts'
ALLOWED='^\.tickets/drafts/DRAFT-[0-9]+\.md$|^report\.md$'

MAX_CRITERIA=5
MAX_TIMEBOX_DAYS=3
# Words that make a criterion untestable. Text in backticks is ignored.
VAGUE='fast|faster|quick|quickly|easy|easily|simple|simply|properly|correctly|appropriate|appropriately|user-friendly|intuitive|robust|seamless|seamlessly|efficient|efficiently|gracefully|reasonable|reasonably|works|handles|should|as expected|etc'

report="${1:-}"
phase="${2:-drafts}"

# Lines under "## <heading>" in a draft, up to the next heading.
dsection() {
  awk -v h="## $2" '$0 == h {f=1; next} /^#/ {f=0} f' "$1"
}
# Non-blank lines of stdin.
nonblank() { grep -v '^[[:space:]]*$' || true; }
# One criterion per line: "- C<n>: ..." plus its indented continuation lines.
criteria_of() {
  dsection "$1" "Acceptance criteria" | awk '
    /^- C[0-9]+:/ { if (c != "") print c; c = $0; next }
    /^[[:space:]]+[^[:space:]]/ && c != "" { sub(/^[[:space:]]+/, " "); c = c $0; next }
    /^[[:space:]]*$/ { next }
    { if (c != "") print c; c = ""; print "STRAY: " $0 }
    END { if (c != "") print c }'
}
# Lines under "<Heading>:" in the report, including text on the heading line.
rsection() {
  awk -v h="$1:" '
    index($0, h) == 1 { f=1; rest=substr($0, length(h)+1); if (rest ~ /[^ ]/) print rest; next }
    /^[A-Z][A-Za-z ()]*:/ { f=0 }
    f' "$report"
}

check_scope "$ALLOWED"
check_secrets

echo "== Drafts in $DRAFTS_DIR"
drafts="$(ls "$DRAFTS_DIR"/DRAFT-*.md 2>/dev/null | sed 's/.*DRAFT-\([0-9]*\)\.md$/\1/' | sort -n || true)"
if [ -z "$drafts" ]; then
  say_fail "no drafts found in $DRAFTS_DIR (expected DRAFT-1.md, DRAFT-2.md, ...)"
fi
expected=1
for n in $drafts; do
  if [ "$n" -ne "$expected" ]; then
    say_fail "drafts must be numbered 1, 2, 3... with no gaps; found DRAFT-$n where DRAFT-$expected was expected"
    break
  fi
  expected=$((n + 1))
done

for n in $drafts; do
  f="$DRAFTS_DIR/DRAFT-$n.md"
  bad=0
  err() { say_fail "DRAFT-$n: $*"; bad=1; }

  head -1 "$f" | grep -Eq "^# DRAFT-$n: [^[:space:]]" || err "first line must be \"# DRAFT-$n: <title>\""
  type="$(grep -E '^Type: ' "$f" | head -1 | sed 's/^Type: *//; s/[[:space:]]*$//')"
  case "$type" in
    Story|Task|Spike) ;;
    *) err "needs a \"Type: Story\", \"Type: Task\", or \"Type: Spike\" line"; type="" ;;
  esac

  for h in "Context" "Out of scope" "Depends on" "Assumptions" "Open questions"; do
    if ! grep -qx "## $h" "$f"; then
      err "missing heading \"## $h\""
    elif [ -z "$(dsection "$f" "$h" | nonblank)" ]; then
      err "\"## $h\" is empty; write \"- None\" if there is nothing"
    fi
  done

  if [ "$type" = "Story" ]; then
    story="$(grep -E '^Story: ' "$f" | head -1)"
    if ! echo "$story" | grep -Eiq '^Story: As an? .+, I want .+, so that .+'; then
      err "needs a line \"Story: As a <user>, I want <goal>, so that <reason>.\""
    else
      echo "$story" | grep -q '`' && err "the Story line must not have code or backticks"
      want="$(echo "$story" | sed -E 's/.*[Ii] want (.*), so that.*/\1/')"
      echo " $want " | grep -Eiq ' and ' && err "the \"I want\" part has \"and\"; one goal per story, so split it"
    fi
  fi

  if [ "$type" = "Story" ] || [ "$type" = "Task" ]; then
    if ! grep -qx "## Acceptance criteria" "$f"; then
      err "missing heading \"## Acceptance criteria\""
    else
      crit="$(criteria_of "$f")"
      count="$(echo "$crit" | grep -c '^- C[0-9]*:' || true)"
      if [ "$count" -eq 0 ]; then
        err "no criteria; write them as \"- C1: ...\""
      elif [ "$count" -gt "$MAX_CRITERIA" ]; then
        err "$count criteria; more than $MAX_CRITERIA means the ticket is too big, so split it"
      fi
      i=1
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        case "$c" in
          STRAY:*) err "line under \"## Acceptance criteria\" isn't a criterion; start each with \"- C<n>:\" and indent wrapped lines: ${c#STRAY: }"; continue ;;
        esac
        id="$(echo "$c" | sed -E 's/^- (C[0-9]+):.*/\1/')"
        [ "$id" = "C$i" ] || err "criteria must be numbered C1, C2, ... in order; found $id where C$i was expected"
        i=$((i + 1))
        echo "$c" | grep -q '`[^`][^`]*`' || err "$id has nothing in backticks to check (a command, endpoint, query, log line, exit code, or file)"
        plain="$(echo "$c" | sed 's/`[^`]*`//g')"
        word="$(echo "$plain" | grep -Eiwo "$VAGUE" | head -1 || true)"
        [ -n "$word" ] && err "$id uses the vague word \"$word\"; say exactly what is observed"
        if echo "$c" | grep -qi '(assumption)'; then
          dsection "$f" "Assumptions" | nonblank | grep -qv '^- None' || err "$id is marked (assumption) but \"## Assumptions\" is None"
        fi
      done <<< "$crit"
    fi
  fi

  if [ "$type" = "Spike" ]; then
    grep -Eq '^Question: .+' "$f" || err "a Spike needs a \"Question: ...\" line"
    tb="$(grep -E '^Timebox: ' "$f" | head -1)"
    days="$(echo "$tb" | sed -nE 's/^Timebox: *([0-9]+) *days?.*/\1/p')"
    if [ -z "$days" ]; then
      err "a Spike needs a \"Timebox: <n> days\" line"
    elif [ "$days" -gt "$MAX_TIMEBOX_DAYS" ]; then
      err "timebox is $days days; the most is $MAX_TIMEBOX_DAYS, so narrow the question"
    fi
    if ! grep -qx "## Expected outcome" "$f"; then
      err "a Spike needs \"## Expected outcome\""
    elif [ -z "$(dsection "$f" "Expected outcome" | nonblank)" ]; then
      err "\"## Expected outcome\" is empty"
    fi
  fi

  # Drafts are numbered in build order, so a draft can only depend on a
  # lower number. That also rules out loops.
  deps="$(dsection "$f" "Depends on" | grep -Eo 'DRAFT-[0-9]+' | sed 's/DRAFT-//' | sort -nu || true)"
  for d in $deps; do
    if [ ! -f "$DRAFTS_DIR/DRAFT-$d.md" ]; then
      err "depends on DRAFT-$d, which doesn't exist"
    elif [ "$d" -ge "$n" ]; then
      err "depends on DRAFT-$d; number drafts in build order so dependencies come first"
    fi
  done

  st="$(grep -inE 'to-do|in progress' "$f" | cut -d: -f1 | tr '\n' ' ' || true)"
  [ -n "$st" ] && err "mentions To-do or In Progress (lines: $st); tickets go to Backlog only"
  st="$(grep -iE '^(state|status):' "$f" | grep -vi 'backlog' || true)"
  [ -n "$st" ] && err "has a state other than Backlog: $st"

  [ "$bad" -eq 0 ] && echo "  OK  DRAFT-$n ($type)"
done

echo "== Cited file lines"
# "path line N" must point at a real file with at least N lines.
cites="$( { cat "$DRAFTS_DIR"/DRAFT-*.md 2>/dev/null; [ -n "$report" ] && [ -f "$report" ] && cat "$report"; } \
  | grep -Eo '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+ lines? [0-9]+' | sort -u || true)"
cite_bad=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  path="$(echo "$c" | sed -E 's/ lines? [0-9]+$//')"
  num="$(echo "$c" | sed -E 's/.* lines? ([0-9]+)$/\1/')"
  if [ ! -f "$path" ]; then
    say_fail "cites \"$c\", but $path doesn't exist"; cite_bad=1
  elif [ "$(wc -l < "$path" | tr -d ' ')" -lt "$num" ]; then
    say_fail "cites \"$c\", but $path is shorter than that; get line numbers from grep -n"; cite_bad=1
  fi
done <<< "$cites"
[ "$cite_bad" -eq 0 ] && echo "All cited files and lines exist."

if [ -n "$report" ]; then
  check_headings "$report" "Mode:" "Goals:" "Security flags:" "Code facts:" "Plan:" "Open questions:" "Needs approval:" "Created:" "Verify:"
  if [ -f "$report" ]; then
    echo "== Report against AGENTS.md and the drafts"
    mode="$(grep -E '^Mode:' "$report" | head -1 | sed 's/^Mode: *//; s/[[:space:]]*$//')"
    target="$(grep -E '^Planner writes tickets to:' AGENTS.md 2>/dev/null | head -1 || true)"
    if [ -z "$target" ]; then
      say_fail "AGENTS.md has no \"Planner writes tickets to:\" line"
    elif echo "$target" | grep -q 'Linear team'; then
      [ "$mode" = "Linear" ] || say_fail "AGENTS.md names a Linear team, so \"Mode:\" must be Linear, found \"$mode\""
    else
      [ "$mode" = "Local" ] || say_fail "AGENTS.md says local drafts, so \"Mode:\" must be Local, found \"$mode\""
    fi

    plan="$(rsection 'Plan')"
    for n in $drafts; do
      echo "$plan" | grep -qw "DRAFT-$n" || say_fail "DRAFT-$n is not listed under \"Plan:\""
    done
    for d in $(echo "$plan" | grep -Eo 'DRAFT-[0-9]+' | sort -u); do
      [ -f "$DRAFTS_DIR/$d.md" ] || say_fail "\"Plan:\" lists $d, but $DRAFTS_DIR/$d.md doesn't exist"
    done

    goals="$(rsection 'Goals' | grep -Eo '^- G[0-9]+' | sed 's/^- //' || true)"
    [ -n "$goals" ] || say_fail "\"Goals:\" has no goals; list them as \"- G1: ...\""
    covered="$(rsection 'Plan'; rsection 'Open questions'; rsection 'Needs approval')"
    for g in $goals; do
      echo "$covered" | grep -qw "$g" || say_fail "goal $g isn't covered by a ticket in \"Plan:\", or listed under \"Open questions:\" or \"Needs approval:\""
    done

    questions="$(rsection 'Open questions')"
    for n in $drafts; do
      if dsection "$DRAFTS_DIR/DRAFT-$n.md" "Open questions" | nonblank | grep -qv '^- None'; then
        echo "$questions" | grep -qw "DRAFT-$n" || say_fail "DRAFT-$n has open questions that aren't under \"Open questions:\" in the report"
      fi
    done

    echo "== Created"
    created="$(rsection 'Created')"
    if [ "$phase" = "created" ]; then
      if [ "$mode" != "Linear" ]; then
        say_fail "the \"created\" check is for Linear mode only"
      else
        for n in $drafts; do
          echo "$created" | grep -Eq "DRAFT-$n -> (exists: )?[A-Z][A-Z0-9]*-[0-9]+" \
            || say_fail "\"Created:\" needs \"- DRAFT-$n -> <ID> <url>\" or \"- DRAFT-$n -> exists: <ID> (not created)\""
        done
      fi
    elif [ "$mode" = "Linear" ]; then
      echo "$created" | grep -q 'Pending' || say_fail "Linear mode: \"Created:\" must say Pending until the drafts pass this check"
    else
      echo "$created" | grep -Eq 'Pending|Local mode' || say_fail "Local mode: \"Created:\" must say \"Local mode, drafts only\""
    fi
    echo "Checked."
  fi
fi

finish "Planner-Agent"
