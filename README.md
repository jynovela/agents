# Agents

Generic agent roles and guardrails to copy into a project and tailor.

## Layout

| Path | Read by | What it holds |
| ---- | ------- | ------------- |
| `AGENTS.md` | Hermes, Codex, Cursor, and most tools | Project basics, shared guardrails, sources of truth, role list |
| `CLAUDE.md` | Claude Code | `@AGENTS.md`, so Claude Code loads the same file |
| `.agents/roles/<name>.md` | Any agent, via the role list in `AGENTS.md` | The full role definition. This is the source of truth. |
| `.claude/agents/<name>.md` | Claude Code (as a subagent) | A thin wrapper that points to the role file |
| `.agents/tools/*.sh` | The agent | Helper scripts a role runs so a small model doesn't do fiddly text work by hand |
| `.agents/checks/<name>.sh` | The agent, and you after a run | Checks in code that back up the written rules (changed files, secrets). `lib.sh` holds the checks every role shares. `lint-guard.sh`, `context-lint.sh`, `secret-scan.sh`, and `spec-diff.sh` serve every agent: see `setup/lint.md`, `setup/security.md`, and `setup/api.md`. |
| `setup/` | You, once per project | Setup guides, plus files they tell you to copy, such as the Ruff config and git hooks |
| `.markdownlint-cli2.yaml` | markdownlint | Default doc lint rules |
| `examples/sample-app/` | You, when testing a role | A small test app with traps and an expected result for each agent. Don't copy it into projects. |

Written rules aren't enough on their own, especially with smaller models. Any
rule that code can check (which files changed, whether a secret leaked) also
gets a check script that fails the run.

Each rule lives in one file. Wrappers point to role files instead of copying
them, so the two can't drift apart.

## Use in a project

1. Copy `AGENTS.md`, `CLAUDE.md`, `.agents/`, `.claude/agents/`, and
   `.markdownlint-cli2.yaml` into the project root.
2. Fill in every `<!-- TAILOR: ... -->` comment: the project overview, stack,
   commands, and each role's verify commands.
3. Remove roles you don't use from the table in `AGENTS.md`.
4. In a monorepo, add a short `AGENTS.md` in a package folder for rules that
   apply only there. Hermes and Codex merge nested files from the repo root
   down to the working folder.

## Set up before using the agents

Agents can only check what they can run. Do these once per project, or the
Test-Agent falls back to unit tests and its report says the criteria are
untested.

1. **A dev environment agents can drive.** Fill in the "Dev environment"
   section of `AGENTS.md` with exact commands: start the app (returning once
   it's healthy), stop it, a health check, the base URL, reset test data, a
   read-only database query, tail the logs, trigger jobs, and the unit and
   acceptance test commands. Use a throwaway local database with seed data,
   never a shared or production one. Write logs to a file agents can tail.
   [examples/sample-app/base/dev/](examples/sample-app/base/dev/) shows small
   scripts for each command.
2. **Access to tickets.** Agents take acceptance criteria from your
   tracker. For Linear, connect the Linear MCP server in Claude Code or
   Hermes, and set the "Tickets" lines in `AGENTS.md`. Test-Agent only reads
   tickets. Planner-Agent also creates them, so name the exact Linear team it
   writes to, and the folders or repos it should read. Write criteria as
   actions anyone can check: "after Y, the X row has status `sent`", "doing A
   writes B to the log", "an offset past the end prints nothing".
3. **A separate agent writes the code.** The agent that writes the tests must
   not write the code that passes them, or it only proves it agrees with
   itself.
4. **Fence the tests while the code agent runs.** In Claude Code, add deny
   rules to `.claude/settings.json`:

   ```json
   {
     "permissions": {
       "deny": ["Edit(/acceptance/**)", "Edit(/tests/**)"]
     }
   }
   ```

   Deny rules don't stop shell commands, and Hermes has no per-path rules, so
   also check after every code agent run that this prints nothing:

   ```sh
   git status --porcelain -- acceptance tests
   ```

5. **Linting that agents can't skip.** Follow
   [setup/lint.md](setup/lint.md): a linter config, a pre-commit hook, a
   Claude Code hook that lints each edited file, and CI. Fill in "Lint code"
   and "Fix lint" in `AGENTS.md`. Most style and safety rules belong there,
   not in prose.
6. **Secret scanning that agents can't skip.** Follow
   [setup/security.md](setup/security.md): gitleaks with a config, a scan in
   the pre-commit hook and in CI, and the "Scan secrets" command in
   `AGENTS.md`. The role check scripts also use gitleaks when it's on the
   `PATH`.
7. **A gate on API changes, if the project has an HTTP API.** Follow
   [setup/api.md](setup/api.md): a check that fails on any spec change that
   isn't additive until you approve it in `.api/approved.md`, Spectral style
   rules, and API guidelines. Fill in "API spec is", "Lint API spec", and
   "Spec diff" in `AGENTS.md`.

### Let Claude do the setup

Claude Code can do most of these steps for you. Open it in the project root
and paste one prompt per setup guide:

```text
Set up API spec checks. Read setup/api.md and follow "Steps for the agent" in order.
```

```text
Set up linting. Read setup/lint.md and do its steps in order. Ask me before you install anything or choose a rule, and don't commit. End with what you did, what failed, and what I still need to do.
```

```text
Set up secret scanning. Read setup/security.md and do its steps in order. Ask me before you install anything, and don't commit. End with what you did, what failed, and what I still need to do.
```

Claude stops to ask where a choice is yours, and it never commits. Commit
the setup files yourself with `git commit --no-verify`: the lint guard blocks
changes to hooks and config, so agents can't loosen them later.

## Workflow: from ticket to merged code

1. Ask the Planner-Agent to plan a brief. It writes tickets with acceptance
   criteria to Linear Backlog (or local drafts) and stops. Read them, fix
   what you disagree with, and move the ones you want to To-do yourself. Or
   write the ticket and its criteria by hand.
2. Ask the Test-Agent for **Write** mode. It writes one acceptance test per
   criterion, and each must fail because the feature isn't built yet.
3. Review the tests yourself before anything else. Check that every assertion
   traces to a criterion, read the assumptions it lists under "Needs
   approval", and add any edge case it missed. Then commit the tests.
4. Hand the ticket to your code agent, with the tests fenced (setup step 4).
   If lint errors are left when it's done, ask the Lint-Agent to fix lint on
   the branch. If the branch touches an endpoint, a CLI flag, or an
   environment variable, ask the API-Agent to check the API. It writes
   additive changes into the spec and lists breaking ones. Approve a breaking
   change by committing its line to `.api/approved.md`, or send the work
   back.
5. Ask the Test-Agent for **Verify** mode. It runs the acceptance tests
   against the running app and reports each criterion with evidence. If
   any criterion fails, send the work back to your code agent and skip
   review until Verify passes.
6. Ask the Review-Agent to review the branch. Run it on a different model
   family than the one that wrote the code, and on the strongest model you
   have: it's the last check before merge. In testing, a dense 31B model
   scored steadily, while a small mixture-of-experts model (about 3B active)
   missed different things on every run. It checks each criterion, scope,
   and design, and gives a verdict. It never edits code.
7. Ask the Security-Agent to review the branch, on the same strong model.
   It runs the secret scanner and security lint, checks what they miss, and
   gives a result of BLOCK, REVIEW, or PASS. It never edits code.
8. Read the verdict, the security result, and the findings, then merge or
   send the work back.

### Claude Code

Ask for a role by name, for example "use the docs-agent to update the docs for
this branch". The `tools` list in a wrapper limits which tools the subagent
gets. To limit which shell commands it can run, add permission rules in
`.claude/settings.json`.

### Hermes

Hermes loads `AGENTS.md` automatically. It has no role files, so ask for the
role by name, for example "act as Docs-Agent". The role list in `AGENTS.md`
tells the model which file to read. Don't add a `.hermes.md` file: Hermes
loads only one project file, and `.hermes.md` takes priority over `AGENTS.md`.

## Roles

| Role | Status |
| ---- | ------ |
| Docs-Agent | Ready |
| Test-Agent | Ready |
| Planner-Agent | Ready |
| Lint-Agent | Ready |
| API-Agent | Testing |
| Build-Agent | Planned |
| Security-Agent | Testing |
| Review-Agent | Ready |
