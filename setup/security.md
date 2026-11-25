# Set up secret scanning for agents

Agents read and write code fast, and they copy what they see. A key in a test,
a log, or a config file ends up in a commit unless code stops it. A rule in
`AGENTS.md` isn't enough: small models forget it, and in testing one leaked a
token into the docs. This setup scans for secrets at every commit and in CI,
with the same scanner and the same config.

| Piece | File to copy | What it does |
| ----- | ------------ | ------------ |
| Scanner config | `setup/gitleaks.toml` | gitleaks' built-in rules, plus your own token formats and fixture paths |
| Secret scan | `.agents/checks/secret-scan.sh` | Runs gitleaks and prints `file:line rule` for each finding, never the value |
| Pre-commit hook | `setup/githooks/pre-commit` | Scans staged files before each commit, then lints them |
| Lint guard | `.agents/checks/lint-guard.sh` | Fails when an agent adds a `gitleaks:allow` comment or edits the scanner config |

The scanner is [gitleaks](https://github.com/gitleaks/gitleaks). It runs
offline, needs no account, and ships as one binary. Tested with v8.30.

## 1. Install gitleaks

```sh
brew install gitleaks
```

On Linux, download a release binary from the gitleaks releases page, or run
`go install github.com/zricethezav/gitleaks/v8@v8.30.1`. Check that it runs
from the same shell your agent uses:

```sh
gitleaks version
```

Without gitleaks, `secret-scan.sh` fails and the pre-commit hook blocks every
commit. That's on purpose: a scan that silently skips looks the same as a
clean one.

## 2. Add the config

Copy `setup/gitleaks.toml` to the project root as `.gitleaks.toml` and fill
in its `TAILOR` comments:

- Add a rule for each token format your company issues, so the scanner knows
  them.
- List folders that hold fake values on purpose, such as test fixtures. Keep
  the list short: every path there is a place a real secret can hide.

Then scan the whole history once:

```sh
gitleaks git --redact --no-banner -v .
```

`--redact` hides the values in the output. For each finding, treat the secret
as leaked (see "When the scanner finds a secret") or, if it's a fake value,
move it under a fixture path.

## 3. Fill in the command in AGENTS.md

```markdown
- Scan secrets: `.agents/checks/secret-scan.sh`
```

The shared guardrails tell every agent to run it before finishing, and to
stop and report any finding by file and line. With no argument it scans
uncommitted changes, including new files. With a base branch, such as
`.agents/checks/secret-scan.sh main`, it also scans every commit on the
branch, so a secret that was added and then deleted still shows up.

## 4. Install the pre-commit hook

If you followed `setup/lint.md`, the hook is already installed: copy the new
`setup/githooks/pre-commit` over `.githooks/pre-commit`. Otherwise:

```sh
mkdir -p .githooks
cp setup/githooks/pre-commit .githooks/
git config core.hooksPath .githooks
```

The hook also runs the linter. If you don't lint yet, set `PATTERN` to a
pattern that matches no files.

## 5. Run the same scan in CI

The hook only runs where it's installed, and anyone can skip it. CI scans
every pull request. For GitHub Actions:

```yaml
name: secrets
on: pull_request
jobs:
  secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Install gitleaks
        run: |
          curl -sSfL -o gitleaks.tar.gz https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
          tar -xzf gitleaks.tar.gz gitleaks
          sudo mv gitleaks /usr/local/bin/
      - run: .agents/checks/secret-scan.sh origin/${{ github.base_ref }}
```

Pin the gitleaks version, so a new release with new rules doesn't fail every
open pull request. Unlike the lint guard, this step blocks: there's no such
thing as an approved leak.

## When the scanner finds a secret

1. **Rotate it first.** Revoke the key where it was issued and make a new
   one. Once a secret is in a commit, assume it's leaked, even on a private
   branch.
2. Move the new value to an environment variable or your secret manager, and
   read it from there in code.
3. Deleting the line doesn't remove it from history. Rewriting history is a
   person's job, and only worth it after rotating.

Agents never do any of this. They report the file and line and stop. They
never copy, move, or print the value, even to "fix" it.

If it's a false positive, a person decides how to allow it: a fixture path in
`.gitleaks.toml`, or a `# gitleaks:allow` comment on the line. Commit it with
`--no-verify`, since the lint guard blocks both for agents.

## What this doesn't catch

gitleaks matches known token formats and long random-looking strings. It
misses short passwords, secrets split across lines, and secrets built at run
time. It also can't tell whether a key is live. The Security-Agent
(planned) reviews what it misses.
