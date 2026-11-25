# Agents

Generic agent roles and guardrails to copy into a project and tailor.

## Layout

| Path | Read by | What it holds |
| ---- | ------- | ------------- |
| `agents/<name>/` | You, and `install.sh` | One folder per agent with everything it owns: `SKILL.md` (the instructions, and the source of truth), `agent.yaml` (what it needs from the project), `check.sh`, `tools/` (helper scripts, so a small model doesn't do fiddly text work by hand), and `claude.md` (the Claude Code wrapper) |
| `skills/<name>/` | You, and `install.sh` | The same shape for a skill: a procedure any agent, or you, can run. It has no wrapper. |
| `shared/` | Every agent | `lib.sh`, the helpers every check script uses, and the checks that serve all agents: `lint-guard.sh`, `context-lint.sh`, `secret-scan.sh`, `spec-diff.sh`, `build-guard.sh`, and `doctor.sh`, which lists what each installed agent still needs. See `setup/lint.md`, `setup/security.md`, `setup/api.md`, and `setup/build.md`. |
| `INSTALL.md` | Claude Code, from the one-prompt setup | The steps to install the agents in a project and set it up for them |
| `install.sh` | You | Copies agents and skills into a project and lists them in its `AGENTS.md` |
| `tests/install-alone.sh` | You and CI, when changing this repo | Proves every agent installs and runs on its own |
| `AGENTS.md` | Hermes, Codex, Cursor, and most tools | Project basics, shared guardrails, sources of truth, agent list |
| `CLAUDE.md` | Claude Code | `@AGENTS.md`, so Claude Code loads the same file |
| `setup/` | You, once per project | Setup guides, plus files they tell you to copy, such as the Ruff config and git hooks. Installed in a project as `.agents/setup/`. |
| `.markdownlint-cli2.yaml` | markdownlint | Default doc lint rules |
| `examples/sample-app/` | You, when testing an agent | A small test app with traps and an expected result for each agent. Don't copy it into projects. |
| `.agents/`, `.claude/` | Tools opened in this repo | Links to `agents/`, `skills/`, and `shared/`, so this repo looks like a project with everything installed. Don't copy them. |

Written rules aren't enough on their own, especially with smaller models. Any
rule that code can check (which files changed, whether a secret leaked) also
gets a check script that fails the run.

Each rule lives in one file. Wrappers point to `SKILL.md` instead of copying
it, so the two can't drift apart.

## Use in a project

### With Claude Code, in one prompt

Open Claude Code in your project's root folder and paste:

```text
Clone https://github.com/jynovela/agents to ~/agents if it isn't there yet, or update it with git pull if it is. Then read ~/agents/INSTALL.md and follow it to set up the agents in this project.
```

Claude installs the agents, fills in `AGENTS.md` from what your project
already has, and works through the setup guides. It asks before it installs
a tool or where a choice is yours, and it never commits. It ends with a list
of which agents are ready and what is left for you. To install only some,
name them in the prompt: "... to set up docs-agent and test-agent in this
project."

### By hand

1. Clone this repo. From it, install everything into your project:

   ```sh
   ./install.sh <project-dir> all
   ```

   Or install only what you want, by folder name:

   ```sh
   ./install.sh <project-dir> docs-agent test-agent
   ```

   In the project this writes:

   | Path | What it holds |
   | ---- | ------------- |
   | `.agents/skills/<name>/` | `SKILL.md`, `agent.yaml`, `check.sh`, and `tools/` for each agent or skill |
   | `.agents/shared/` | `lib.sh`, `doctor.sh`, and the shared checks |
   | `.agents/setup/` | The setup guides and the files they tell you to copy |
   | `.claude/agents/<name>.md` | The Claude Code wrapper for each agent |
   | `.claude/skills/<name>` | A link to each skill, so Claude Code finds it |
   | `AGENTS.md` | Created from this repo's copy when the project has none. In an existing one, only the tables of installed agents change: the part between the `agents:start` and `agents:end` comments. |
   | `CLAUDE.md`, `.markdownlint-cli2.yaml` | Created only when the project has none |

   Running it again replaces the files under `.agents/` and `.claude/` with
   this repo's version, and adds what you newly installed to the tables. It
   never commits.
2. In the project's `AGENTS.md`, fill in every `<!-- TAILOR: ... -->`
   comment: the project overview, stack, and commands. Do the same in the
   `SKILL.md` of each agent you installed.
3. See what each agent still needs. The install prints this, and you can
   run it again at any time from the project:

   ```sh
   .agents/shared/doctor.sh
   ```

   `READY` means the agent has every `AGENTS.md` line and tool it needs.
   `NOT READY` lists what to set or install, and the setup guide to read.
   An agent that isn't ready doesn't stop the others from working.
4. Do the setup the agents need. [setup/README.md](setup/README.md) lists
   it: a dev environment agents can drive, access to tickets, linting and
   secret scanning that agents can't skip, a gate on API changes, staging,
   and demo data. In the project the same file is `.agents/setup/README.md`.
5. In a monorepo, add a short `AGENTS.md` in a package folder for rules that
   apply only there. Hermes and Codex merge nested files from the repo root
   down to the working folder.

## Workflow: from ticket to merged code

1. Ask the Planner-Agent to plan a brief. It writes tickets with acceptance
   criteria to Linear Backlog (or local drafts) and stops. Read them, fix
   what you disagree with, and move the ones you want to To-do yourself. Or
   write the ticket and its criteria by hand.
2. If the ticket changes an endpoint, ask the API-Agent for **Design** mode
   first. It writes the additive parts of the ticket into the spec and lists
   breaking ones for approval. Review the spec diff and commit it, along with
   any approval lines you add to `.api/approved.md`. Tests and code are then
   written against that spec.
3. Ask the Test-Agent for **Write** mode. It writes one acceptance test per
   criterion, and each must fail because the feature isn't built yet.
4. Review the tests yourself before anything else. Check that every assertion
   traces to a criterion, read the assumptions it lists under "Needs
   approval", and add any edge case it missed. Then commit the tests.
5. Hand the ticket to your code agent, with the tests fenced (step 4 in `setup/README.md`).
   If lint errors are left when it's done, ask the Lint-Agent to fix lint on
   the branch. If the branch touches an endpoint, a CLI flag, or an
   environment variable, ask the API-Agent to check the API. It writes
   additive changes into the spec and lists breaking ones. Approve a breaking
   change by committing its line to `.api/approved.md`, or send the work
   back.
   If the build fails, ask the Build-Agent why. It fixes build
   scripts and names the owner of every other cause. Commit its fixes as
   their own commit, so review doesn't count them as scope creep.
6. Ask the Test-Agent for **Verify** mode. It runs the acceptance tests
   against the running app and reports each criterion with evidence. If
   any criterion fails, send the work back to your code agent and skip
   review until Verify passes.
7. Ask the Review-Agent to review the branch. Run it on a different model
   family than the one that wrote the code, and on the strongest model you
   have: it's the last check before merge. In testing, a dense 31B model
   scored steadily, while a small mixture-of-experts model (about 3B active)
   missed different things on every run. It checks each criterion, scope,
   and design, and gives a verdict. It never edits code.
8. Ask the Security-Agent to review the branch. It runs the secret scanner
   and security lint, checks what they miss, and gives a result of BLOCK,
   REVIEW, or PASS. It never edits code. In testing, a small model (about 3B
   active) scored 13, 11, and 13 of 14 against a frontier model's 13, because
   the scanners and check script do most of the work. Its misses were
   judgment calls like path traversal, so for risky changes (auth, file
   handling, new endpoints) run it on your strongest model too.
9. Read the verdict, the security result, and the findings, then merge or
   send the work back.
10. Test on staging before it goes live. Ask the Build-Agent to deploy to
   staging (or let your host build the preview), and click through the
   change. Then release to production yourself. No agent can.

### Claude Code

Ask for a role by name, for example "use the docs-agent to update the docs for
this branch". The `tools` list in a wrapper limits which tools the subagent
gets. To limit which shell commands it can run, add permission rules in
`.claude/settings.json`.

### Hermes

Hermes loads `AGENTS.md` automatically. Ask for the agent by name, for
example "act as Docs-Agent". The agent list in `AGENTS.md` tells the model
which `SKILL.md` to read. Don't add a `.hermes.md` file: Hermes
loads only one project file, and `.hermes.md` takes priority over `AGENTS.md`.

## Roles

| Role | Status |
| ---- | ------ |
| Docs-Agent | Ready |
| Test-Agent | Ready |
| Planner-Agent | Ready |
| Lint-Agent | Ready |
| API-Agent | Ready |
| Build-Agent | Ready |
| Security-Agent | Ready |
| Review-Agent | Ready |
| Implementer-Agent | Built, not yet tested on a small model |
