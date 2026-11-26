# Agents

A set of AI agents you install into a software project so it gets built
test-first. You approve what "done" means for a ticket. The agents write
the tests from that, write the code that passes them, update the docs,
review the change, and check it for security problems. You try the result
on staging and release it yourself.

What you gain:

- **Code that is proven against your criteria.** Every acceptance criterion
  becomes a test that fails before the code exists and passes after. A
  different agent writes the code than the one that wrote the tests, so the
  code can't grade itself.
- **Two check-ins for you, not twenty.** You approve the acceptance criteria
  at the start, and you test on staging at the end. The steps in between
  are the agents' work.
- **Rules that hold with cheap models.** Each agent has one job, a short
  list of files it may change, and a check script that fails the run when
  it breaks a rule: a leaked secret, a skipped test, an edit outside its
  scope. The rules don't depend on the model obeying them.
- **Your choice of model per agent.** The agents are plain Markdown files
  and shell scripts. Run them all in Claude Code, or run most of them on a
  local open-weight model and keep a strong model for review.
- **No agent can release.** Agents deploy to local and staging only.
  Production is yours.

Each agent also works alone. Install only Docs-Agent to keep docs in step
with code, or only Security-Agent to review branches.

## What you need

<details>
<summary>Tools and accounts</summary>

| You need | For | Notes |
| -------- | --- | ----- |
| A project in a git repository | Everything | The agents are installed into it. An empty repository is fine. |
| [Claude Code](https://claude.com/claude-code) | Running the agents, and the one-prompt install | Or another agent tool that reads `AGENTS.md`, such as Hermes with a local model. Claude Code is the simplest start. |
| [Linear](https://linear.app), connected to your agent tool through its MCP server | Tickets and acceptance criteria | Optional. Without it, tickets are Markdown files in the project. |
| Node.js | The doc lint (`npx markdownlint-cli2`) and the API spec lint | |
| [gitleaks](https://github.com/gitleaks/gitleaks) | Secret scanning | The setup installs it with your approval. |
| [oasdiff](https://github.com/oasdiff/oasdiff) | The gate on API changes | Only if the project has an HTTP API. |
| A linter for your language | Lint-Agent and the lint hook | The guide uses Ruff for Python. |
| A staging environment | Trying a change before release | Can wait until you have something to deploy. |

You don't need all of it on day one. After the install, one command lists
which agents are ready and what each of the others is missing.

</details>

## Install

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

<details>
<summary>Install with the script, step by step</summary>

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

</details>

## Set up

<details>
<summary>Setup steps</summary>

The install copies the agents. The setup gives them what they need to check
their own work: commands they can run, tickets they can read, and hooks
they can't skip. The one-prompt install does most of it. By hand:

1. In the project's `AGENTS.md`, fill in every `<!-- TAILOR: ... -->`
   comment: the project overview, the stack, and the commands. Do the same
   in the `SKILL.md` of each agent you installed.
2. Work through [setup/README.md](setup/README.md). In the project the same
   file is `.agents/setup/README.md`. It covers:

   | Setup | Why |
   | ----- | --- |
   | A dev environment agents can drive | Tests run against the real app, not mocks |
   | Access to tickets | Agents read the acceptance criteria you approved |
   | Fenced tests | The agent writing code can't edit the tests it must pass |
   | Linting and secret scanning in a git hook and CI | Agents can't skip them |
   | A gate on API changes | A breaking change needs your approval |
   | Staging, and a production only you can deploy | You try changes safely, and no agent can release |
   | Demo data, if the project has a UI | Every screen state can be seen live |

3. Run `.agents/shared/doctor.sh` again until the agents you want say
   `READY`.
4. Commit the setup yourself with `git commit --no-verify`. The lint guard
   blocks changes to hooks and config, so agents can't loosen them later.
5. In a monorepo, add a short `AGENTS.md` in a package folder for rules that
   apply only there. Hermes and Codex merge nested files from the repo root
   down to the working folder.

</details>

## Workflow

<details>
<summary>The two tracks, step by step</summary>

There are two tracks. Planning turns an idea into tickets. Doing turns one
ticket into tested code on staging. Today you start each agent yourself, in
this order. A runner that does the Doing track from one command is the next
thing being built.

### Planning: from an idea to tickets

1. *Optional, for a project with a UI.* Run the `user-flows` skill on your
   research or brief, the `design-system` skill once per project, and then
   Design-Agent. You get flow files, screen specs, and clickable low-fi
   wireframes.
2. Ask Planner-Agent to plan a brief. It writes tickets with acceptance
   criteria to Linear Backlog, or to local drafts, and stops.
3. **Your check-in: approve the acceptance criteria.** Read the tickets, fix
   what you disagree with, and move the ones you want to To-do. Everything
   after this is tested against those criteria, so this is where your
   attention pays most.

### Doing: from one ticket to staging

1. If the ticket changes an endpoint, ask API-Agent for **Design** mode. It
   writes the additive parts into the API spec and lists breaking ones for
   your approval in `.api/approved.md`.
2. Ask Test-Agent for **Write** mode. It writes one acceptance test per
   criterion. Each must fail, because the feature isn't built yet.
3. Ask Implementer-Agent to build the ticket. It writes the smallest code
   change that makes the tests pass and can't edit the tests.
4. Ask Test-Agent for **Verify** mode. It runs the tests against the
   running app and reports each criterion with evidence. If one fails, the
   work goes back to step 3.
5. Ask Docs-Agent to update the docs for the branch.
6. Ask Review-Agent and Security-Agent to review the branch. Neither edits
   code. Review gives a verdict against the ticket. Security runs the
   scanners, checks what they miss, and answers BLOCK, REVIEW, or PASS. If
   either rejects, the work goes back to step 3.
7. Ask Build-Agent to deploy to staging, or let your host build a preview.
8. **Your check-in: test on staging.** If it does what you wanted, merge
   and release to production yourself. No agent can.

Three agents are on call and not steps. Call Lint-Agent when lint errors
are left on a branch, Build-Agent when the build fails, and API-Agent's
check mode when a branch touched an endpoint, a CLI flag, or an environment
variable.

### Which model for which agent

Run Review-Agent on a different model family than the one that wrote the
code, and on the strongest model you have. In testing, a dense 31B model
scored steadily, while a small mixture-of-experts model (about 3B active)
missed different things on every run. Security-Agent held up on the small
model (13, 11, and 13 of 14, against a frontier model's 13), because the
scanners and its check script do most of the work. Its misses were judgment
calls like path traversal, so for risky changes (auth, file handling, new
endpoints) run it on your strongest model too.

### Start an agent in Claude Code

Ask for a role by name, for example "use the docs-agent to update the docs for
this branch". The `tools` list in a wrapper limits which tools the subagent
gets. To limit which shell commands it can run, add permission rules in
`.claude/settings.json`.

### Start an agent in Hermes

Hermes loads `AGENTS.md` automatically. Ask for the agent by name, for
example "act as Docs-Agent". The agent list in `AGENTS.md` tells the model
which `SKILL.md` to read. Don't add a `.hermes.md` file: Hermes
loads only one project file, and `.hermes.md` takes priority over `AGENTS.md`.

To give each agent its own Hermes profile, with its own `SOUL.md` and its
own model, follow [HERMES.md](HERMES.md). That is how you run most agents on
a cheap local model and keep a strong one for review.

</details>

## Layout

<details>
<summary>What each folder holds</summary>

What is in this repo, for when you want to read or change an agent.

| Path | Read by | What it holds |
| ---- | ------- | ------------- |
| `agents/<name>/` | You, and `install.sh` | One folder per agent with everything it owns: `SKILL.md` (the instructions, and the source of truth), `agent.yaml` (what it needs from the project), `check.sh`, `tools/` (helper scripts, so a small model doesn't do fiddly text work by hand), `claude.md` (the Claude Code wrapper), and `hermes/SOUL.md` (the Hermes profile's identity file) |
| `skills/<name>/` | You, and `install.sh` | The same shape for a skill: a procedure any agent, or you, can run. It has no wrapper. |
| `shared/` | Every agent | `lib.sh`, the helpers every check script uses, and the checks that serve all agents: `lint-guard.sh`, `context-lint.sh`, `secret-scan.sh`, `spec-diff.sh`, `build-guard.sh`, and `doctor.sh`, which lists what each installed agent still needs. See `setup/lint.md`, `setup/security.md`, `setup/api.md`, and `setup/build.md`. |
| `HERMES.md`, `hermes/profiles.sh` | You, when using Hermes | How to give each agent its own Hermes profile, and the script that creates them |
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

</details>

## Roles

<details>
<summary>Every agent and skill, with its status</summary>

| Agent | What it does | Status |
| ----- | ------------ | ------ |
| Planner-Agent | Turns a brief into tickets with testable acceptance criteria, then stops | Ready |
| Design-Agent | Turns a user flow into screen specs and clickable low-fi wireframes | In testing |
| API-Agent | Keeps the API spec in step with the code. Lists breaking changes for your approval | Ready |
| Test-Agent | Turns acceptance criteria into tests against the running app, then verifies the code with real results | Ready |
| Implementer-Agent | Writes the smallest code change that makes one ticket's tests pass | Built, not yet tested on a small model |
| Docs-Agent | Keeps Markdown docs in step with the code and flags API spec drift | Ready |
| Review-Agent | Reviews a branch against its ticket and gives a verdict. Never edits code | Ready |
| Security-Agent | Reviews a branch for security problems after the scanners run. Never edits code | Ready |
| Lint-Agent | Makes lint pass on a branch's changed files without changing behavior | Ready |
| Build-Agent | Finds why the build fails and fixes build scripts only. Deploys to staging, never to production | Ready |

| Skill | What it does | Status |
| ----- | ------------ | ------ |
| `user-flows` | Turns journeys, research, or a brief into flow files for Design-Agent | In testing |
| `design-system` | Sets up the project's design system once | In testing |

"Ready" means the agent passed its checklist in `examples/sample-app/` on a
small local model as well as on Claude.

</details>
