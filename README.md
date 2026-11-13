# Agents

Generic agent roles and guardrails to copy into a project and tailor.

## Layout

| Path | Read by | What it holds |
| ---- | ------- | ------------- |
| `AGENTS.md` | Hermes, Codex, Cursor, and most tools | Project basics, shared guardrails, sources of truth, role list |
| `CLAUDE.md` | Claude Code | `@AGENTS.md`, so Claude Code loads the same file |
| `.agents/roles/<name>.md` | Any agent, via the role list in `AGENTS.md` | The full role definition. This is the source of truth. |
| `.claude/agents/<name>.md` | Claude Code (as a subagent) | A thin wrapper that points to the role file |
| `.agents/checks/<name>.sh` | The agent, and you after a run | Checks in code that back up the written rules (changed files, secrets). `lib.sh` holds the checks every role shares. |
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
2. **Read-only access to tickets.** Agents take acceptance criteria from your
   tracker. For Linear, connect the Linear MCP server in Claude Code or
   Hermes, and set the "Tickets" line in `AGENTS.md`. Write criteria as
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

5. **Optional: install gitleaks.** The check scripts use it when it's on the
   `PATH`, on top of their built-in pattern check.

## Workflow: from ticket to merged code

1. Write the acceptance criteria in the ticket.
2. Ask the Test-Agent for **Write** mode. It writes one acceptance test per
   criterion, and each must fail because the feature isn't built yet.
3. Review the tests yourself before anything else. Check that every assertion
   traces to a criterion, read the assumptions it lists under "Needs
   approval", and add any edge case it missed. Then commit the tests.
4. Hand the ticket to your code agent, with the tests fenced (setup step 4).
5. Ask the Test-Agent for **Verify** mode. It runs the acceptance tests
   against the running app and reports each criterion with evidence.
6. Review the diff and merge.

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
| Lint/Style-Agent | Planned |
| API-Agent | Planned |
| Build-Agent | Planned |
| Security-Agent | Planned |
| Review-Agent | Planned |
