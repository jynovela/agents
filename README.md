# Agents

Generic agent roles and guardrails to copy into a project and tailor.

## Layout

| Path | Read by | What it holds |
| ---- | ------- | ------------- |
| `AGENTS.md` | Hermes, Codex, Cursor, and most tools | Project basics, shared guardrails, sources of truth, role list |
| `CLAUDE.md` | Claude Code | `@AGENTS.md`, so Claude Code loads the same file |
| `.agents/roles/<name>.md` | Any agent, via the role list in `AGENTS.md` | The full role definition. This is the source of truth. |
| `.claude/agents/<name>.md` | Claude Code (as a subagent) | A thin wrapper that points to the role file |
| `.markdownlint-cli2.yaml` | markdownlint | Default doc lint rules |
| `examples/sample-app/` | You, when testing a role | A small test app with traps and an expected result for each agent. Don't copy it into projects. |

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
| Test-Agent | Planned |
| Lint/Style-Agent | Planned |
| API-Agent | Planned |
| Build-Agent | Planned |
| Security-Agent | Planned |
| Review-Agent | Planned |
