# Set up linting for agents

Put every rule a tool can check in the linter config and hooks. Keep it out of
`AGENTS.md`. A rule in a config runs every time. A rule in prose works only
when the model remembers it, and small models forget.

This setup gives every agent, including the one that writes your code, the
same feedback loop: it edits a file, the linter reports, and it fixes the
code. Code checks also block the shortcuts agents take to make lint pass.

| Piece | File to copy | What it does |
| ----- | ------------ | ------------ |
| Linter config | `setup/ruff.toml` | Rules that catch common agent mistakes |
| Lint guard | `.agents/checks/lint-guard.sh` | Fails on new suppression comments, lint config edits, leftover files like `app_old.py`, and `--no-verify` |
| Context lint | `.agents/checks/context-lint.sh` | Checks `AGENTS.md`, role files, and wrappers: length, file references that no longer exist, leftover TODOs, frontmatter |
| Pre-commit hook | `setup/githooks/pre-commit` | Runs the linter on staged files, then both checks |
| Claude Code hook | `setup/claude-lint-hook.sh` | Lints each file right after Claude edits it |

The examples use Ruff for Python. For another stack, see "Other stacks" at
the end.

## 1. Install the linter

```sh
pip3 install --user ruff
```

Or `brew install ruff`. Check that it runs from the same shell your agent
uses (Hermes uses the system Python):

```sh
ruff --version
```

If `ruff` isn't found after a `--user` install, `python3 -m ruff --version`
works too. Then use `python3 -m ruff` in place of `ruff` in the commands below.

## 2. Add the config

Copy `setup/ruff.toml` to the project root and fill in its `TAILOR`
comments: the Python version, files that may print, and banned APIs.

Each rule group in it is there for a reason:

| Rules | Catches |
| ----- | ------- |
| `E722`, `BLE`, `S110`, `S112` | Swallowed errors: bare `except`, `except Exception`, `except: pass` |
| `ASYNC` | Blocking calls such as `time.sleep` or `open` inside `async` functions |
| `S` | Security issues: `eval`, `shell=True`, SQL built from strings, hardcoded passwords |
| `T20`, `ERA` | `print` left in from debugging, commented-out code |
| `TID251` | Calls to APIs you've banned, with a message that names the helper to use |
| `PGH004`, `RUF100` | A `# noqa` with no rule code, or one that suppresses nothing |

Run it once over the existing code:

```sh
ruff check --statistics .
```

If that prints hundreds of errors, don't ask an agent to fix them all in one
go. Fix what Ruff can fix by itself with `ruff check --fix .`, review the
diff, and commit it. For the rest, turn off the noisy rules in the config for
now and turn them back on one at a time.

## 3. Fill in the commands in AGENTS.md

Agents run these to check their work:

```markdown
- Lint code: `ruff check . && ruff format --check .`
- Fix lint: `ruff check --fix . && ruff format .`
- Lint guard: `.agents/checks/lint-guard.sh`
- Lint agent files: `.agents/checks/context-lint.sh`
```

The shared guardrails in `AGENTS.md` already tell every agent to fix lint
and never silence it.

## 4. Install the pre-commit hook

From the repo root:

```sh
mkdir -p .githooks
cp setup/githooks/pre-commit .githooks/
git config core.hooksPath .githooks
```

Set `LINT`, `FORMAT_CHECK`, and `PATTERN` at the top of the hook if you
don't use Ruff. Each clone runs the `git config` line once.

Commit the hook yourself, with `git commit --no-verify`. The guard blocks
changes to `.githooks/` and `.agents/checks/`, so without the flag the hook
blocks its own first commit.

Only a person approves a suppression comment or a lint config change. When
you approve one, commit it with `--no-verify`. Agents never use that flag.

## 5. Add the Claude Code hook

This hook runs after every file Claude edits. It formats the file, applies
safe fixes, and sends any remaining errors back to Claude, which fixes them
in the same turn. It doesn't remove unused imports, because Claude often
adds an import one edit before the code that uses it.

```sh
mkdir -p .claude/hooks
cp setup/claude-lint-hook.sh .claude/hooks/lint-file.sh
```

Then add this to `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|MultiEdit|Write",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/lint-file.sh" }
        ]
      }
    ]
  }
}
```

## 6. Hermes

Hermes documents shell hooks in its profile config (`~/.hermes/config.yaml`),
so they apply to every project, not just one repo. Their exact format isn't
verified here, so this setup doesn't depend on them. Hermes gets lint feedback
from three places instead:

- The shared guardrail in `AGENTS.md`, which tells it to run "Lint code" and
  "Lint guard" before it finishes.
- The pre-commit hook, when it commits.
- The role check scripts you run after each agent run.

If you get a Hermes hook working, point it at `setup/claude-lint-hook.sh`.
Its input format may differ.

## 7. Run the same checks in CI

The hook only runs on machines where it's installed. CI runs the same checks
on every pull request. Use the one project workflow in `setup/ci.yml` (see
`setup/build.md`). It installs Ruff at a pinned version, runs "Lint code" and
`context-lint.sh`, and runs the lint guard. Pin the Ruff version so a new
release doesn't fail every open pull request.

The lint guard doesn't block in CI. A suppression you approved would fail it
on every run, and CI can't tell an approved one from a shortcut. It shows up
as a failed step for the reviewer to read. `build-guard.sh` allows
`continue-on-error` on this one step.

## 8. Turn repeated mistakes into rules

When you see the same mistake twice in review, don't add a sentence to
`AGENTS.md`. Add a rule:

1. If Ruff has a rule for it, add the rule code to `select`.
2. If agents call an API instead of your helper, ban the API under
   `[lint.flake8-tidy-imports.banned-api]`, with a message that names the
   helper.
3. Otherwise, add a `grep` check to a script in `.agents/checks/`. Print
   `file:line` and what to do instead.

Test each new rule on the existing code before you commit it.

## Lint-Agent

With this setup, most lint errors get fixed while the code is written. The
Lint-Agent (`.agents/roles/lint-agent.md`) handles what's left: errors
autofix can't fix, and old errors when you turn on a new rule. It fixes only
safe rules by hand and lists the rest for you to approve. Point it at a
folder to clean up old errors one folder at a time.

## Other stacks

This setup is tested only with Ruff. For other linters, the same ideas
apply. For example, for JavaScript or TypeScript with ESLint:

- `linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: "error" }`
  in `eslint.config.js` turns off `eslint-disable` comments entirely, so the
  linter itself blocks suppressions.
- `no-empty` catches empty `catch` blocks, `no-console` catches leftover
  logging, `no-restricted-imports` bans APIs, and
  `@typescript-eslint/no-explicit-any` catches `any`.
- Set `LINT='npx eslint'`, `FORMAT_CHECK='npx prettier --check'`, and
  `PATTERN='\.(js|jsx|ts|tsx)$'` in the pre-commit hook.
