#!/usr/bin/env bash
# Prints a branch's change for a security review, in a form that is easy to
# cite. Long values that could be secrets show as <long value hidden>; quote
# the part of the line before them.
#
# Sections:
#   Changed files          every file the branch changed
#   Added lines            "<file>:<line>: <text>", line numbers as the file is now
#   Harness files          files that tell agents or tools what to do (AGENTS.md,
#                          .claude/, hooks, CI, MCP config). Changes here can give
#                          an agent more power.
#   Dependency files       files that pull in third-party code
#   Risky lines            added lines that often carry a vulnerability, tagged
#                          with what to check, plus every line a scanner flagged.
#                          The report must account for each one.
#
# Usage: .agents/skills/security-agent/tools/security-diff.sh [base]   (default base: main)
# Compares <base>...HEAD, the same range a pull request shows.

set -uo pipefail
base="${1:-main}"
here="$(cd "$(dirname "$0")" && pwd)"

# <!-- TAILOR: patterns for your stack. Each tag names what to check. -->
INJECTION='execute\(|executemany\(|\.raw\(|SELECT |INSERT |UPDATE |DELETE |subprocess|os\.system|os\.popen|shell=True|eval\(|exec\(|pickle\.|yaml\.load|marshal\.|open\(|os\.path\.join|send_file|render_template_string|Markup\(|innerHTML|dangerouslySetInnerHTML|child_process|urlopen\(|requests\.(get|post)|fetch\('
AUTH='\.path ==|path\.startswith\(|def do_(GET|POST|PUT|PATCH|DELETE)|@app\.|@router\.|\.route\(|(app|router)\.(get|post|put|patch|delete)\(|[Tt]oken|[Aa]uth|[Aa]dmin|[Rr]ole|[Pp]ermission|[Ss]ession|[Pp]assw|[Ll]ogin'
SECRET='[Ss]ecret|[Pp]assw|[Aa]pi_?[Kk]ey|[Pp]rivate_?[Kk]ey|[Cc]redential|[Tt]oken'
AGENT_TEXT='([^A-Za-z]|^)(AI|LLM|[Aa]gents?|[Aa]ssistants?|[Cc]laude|[Cc]opilot|[Rr]eviewers?)([^A-Za-z]|$)'
HARNESS='(^|/)(AGENTS\.md|CLAUDE\.md|\.claude/|\.agents/|\.githooks/|\.husky/|\.github/|\.gitlab-ci\.yml|\.mcp\.json|\.cursor/|\.vscode/|skills/|\.gitleaks\.toml|\.gitleaksignore|\.pre-commit-config\.yaml)'
DEPS='(^|/)(requirements[^/]*\.txt|pyproject\.toml|Pipfile(\.lock)?|poetry\.lock|uv\.lock|setup\.py|setup\.cfg|package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|go\.(mod|sum)|Cargo\.(toml|lock)|Gemfile(\.lock)?)$'

# <!-- TAILOR: well-known package names. A new dependency one or two letters
# off one of these, but not equal to it, gets a typo-of:<name> tag. -->
POPULAR='requests urllib3 numpy pandas django flask fastapi pydantic sqlalchemy boto3 botocore pyyaml cryptography jinja2 pillow setuptools click rich pytest httpx aiohttp celery redis psycopg2 scipy matplotlib python-dateutil express react lodash axios chalk commander dotenv'

# Prints "typo-of:<name>" when $1 (a package name) is within two edits of a
# popular name without matching it.
typo_of() {
  python3 - "$1" "$POPULAR" <<'PY' 2>/dev/null
import sys
name = sys.argv[1].lower()
def dist(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]
popular = sys.argv[2].split()
if len(name) >= 4 and name not in popular:
    for p in popular:
        if dist(name, p) <= 2:
            print("typo-of:" + p)
            break
PY
}

hide() { sed -E 's/[A-Za-z0-9_+\/=-]{24,}/<long value hidden>/g'; }

if ! git rev-parse --verify -q "$base" >/dev/null; then
  echo "Base branch \"$base\" not found. Pass the right one, like: .agents/skills/security-agent/tools/security-diff.sh develop" >&2
  exit 1
fi

files="$(git diff --name-only "$base...HEAD")"
echo "== Changed files ($base...HEAD)"
if [ -n "$files" ]; then echo "$files"; else echo "None."; fi

lines="$(git --no-pager diff -U0 --no-color "$base...HEAD" | awk '
  /^\+\+\+ / { file = substr($0, 7); next }
  /^--- /    { next }
  /^@@ /     { split($3, a, ","); line = substr(a[1], 2) + 0; next }
  /^\+/      { print file ":" line ": " substr($0, 2); line++; next }
')"
echo
echo "== Added lines"
if [ -n "$lines" ]; then echo "$lines" | hide; else echo "None."; fi

echo
echo "== Harness files"
harness="$(echo "$files" | grep -E "$HARNESS" || true)"
if [ -n "$harness" ]; then echo "$harness"; else echo "None."; fi

echo
echo "== Dependency files"
deps="$(echo "$files" | grep -E "$DEPS" || true)"
if [ -n "$deps" ]; then echo "$deps"; else echo "None."; fi

# Lines a scanner flagged, as "<file>:<line> <tag>".
scanned=""
if command -v gitleaks >/dev/null 2>&1 && [ -x "$here/../../../shared/secret-scan.sh" ]; then
  scanned="$("$here/../../../shared/secret-scan.sh" "$base" 2>/dev/null | sed -nE 's/^FAIL: ([^ ]+:[0-9]+) ([^ ]+) \(value not shown\)$/\1 secret-scan:\2/p')"
fi
pyfiles="$(echo "$files" | grep -E '\.py$' || true)"
# Hermes and some agent shells don't have pip's user bin folder on PATH, so
# fall back to running Ruff as a Python module.
RUFF=""
if command -v ruff >/dev/null 2>&1; then
  RUFF="ruff"
elif python3 -m ruff --version >/dev/null 2>&1; then
  RUFF="python3 -m ruff"
fi
if [ -n "$RUFF" ] && [ -n "$pyfiles" ]; then
  existing=""
  for f in $pyfiles; do [ -f "$f" ] && existing="$existing $f"; done
  if [ -n "$existing" ]; then
    # shellcheck disable=SC2086
    scanned="$scanned
$($RUFF check --select S --output-format concise --no-cache $existing 2>/dev/null | sed -nE 's/^([^:]+):([0-9]+):[0-9]+: ([A-Z]+[0-9]+).*/\1:\2 ruff:\3/p')"
  fi
fi

echo
echo "== Security lint"
if [ -z "$pyfiles" ]; then
  echo "No .py files changed."
elif [ -n "$RUFF" ]; then
  echo "Ran: $RUFF check --select S. Its hits are tagged ruff:<code> below."
else
  echo "RUFF NOT INSTALLED: Ruff's hits are missing from the risky lines. Install it with: brew install ruff (or pipx install ruff)"
fi

echo
echo "== Risky lines"
out="$(echo "$lines" | while IFS= read -r l; do
  [ -n "$l" ] || continue
  # Skip lines with nothing to check, like a lone "}" in a JSON file.
  echo "${l#*: }" | grep -q '[A-Za-z0-9]' || continue
  loc="$(echo "$l" | cut -d: -f1,2)"
  text="${l#*: }"
  file="${loc%:*}"
  tags=""
  if echo "$text" | grep -Eq '^[[:space:]]*(#|//|<!--|\*)'; then
    # A comment: only check it for text aimed at agents.
    echo "$text" | grep -Eq "$AGENT_TEXT" && tags="$tags,agent-text"
  else
    echo "$text" | grep -Eq "$INJECTION" && tags="$tags,injection"
    echo "$text" | grep -Eq "$AUTH" && tags="$tags,auth"
    echo "$text" | grep -Eq "$SECRET" && tags="$tags,secret"
    echo "$text" | grep -Eq "$AGENT_TEXT" && tags="$tags,agent-text"
    echo "$file" | grep -Eq "$HARNESS" && tags="$tags,harness"
    if echo "$file" | grep -Eq "$DEPS"; then
      tags="$tags,dependency"
      pkg="$(echo "$text" | sed -nE 's/^[[:space:]"]*([A-Za-z0-9_.-]+).*/\1/p')"
      t="$( [ -n "$pkg" ] && typo_of "$pkg" )"
      [ -n "$t" ] && tags="$tags,$t"
    fi
  fi
  for s in $(printf '%s\n' "$scanned" | awk -v k="$loc" '$1 == k {print $2}'); do
    tags="$tags,$s"
  done
  [ -n "$tags" ] && echo "$loc [${tags#,}]: $text"
done)"
if [ -n "$out" ]; then echo "$out" | hide; else echo "None."; fi
