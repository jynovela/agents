# The pipeline: one ticket, from criteria to a branch you can test

`ticket.sh` runs one ticket through the agents in a fixed order. This file
says what the order is and why. In a project it is installed as
`.agents/flow/`.

## Who does what

| Who | Does |
| --- | ---- |
| You | Approve the ticket's acceptance criteria before the run. Test the result after it. Push, merge, and release. |
| The coordinator | Starts the agent the script names, then calls the script again. Claude Code does this with the `run-ticket` skill. A person can do it by hand. |
| `ticket.sh` | Decides the next step, runs each agent's check script, saves each report, and commits each step. It never starts an agent. |
| The agents | One job each, as their `SKILL.md` says. |

The order is in a script, not in a model's judgment, so a cheap model can
coordinate and the run goes the same way every time.

## The order

| Step | Agent | Runs when | If it goes wrong |
| ---- | ----- | --------- | ---------------- |
| 1 | API-Agent, Design mode | You started with `--api`: the ticket adds or changes an endpoint, a CLI flag, or an environment variable | |
| 2 | Test-Agent, Write mode | Always | |
| 3 | Implementer-Agent | Always | It stopped, or a test still fails after its tries: the run stops and asks you |
| 3a | Lint-Agent | The Implementer's report says lint is needed | |
| 3b | API-Agent, Check mode | The Implementer's report says the API changed, and the project has a spec | |
| 4 | Test-Agent, Verify mode | Always | A criterion fails: back to step 3 |
| 5 | Docs-Agent | Always | |
| 6 | Review-Agent | Always | REJECTED: back to step 3 |
| 7 | Security-Agent | Always | BLOCK: back to step 3. REVIEW: the run goes on, and you are told to read it |
| 8 | Build-Agent, deploy to staging | `AGENTS.md` has a "Deploy" command | |

Then the script prints `DONE`, and you test.

## The rules the script applies

- **Check after every agent.** The script runs the agent's own `check.sh`.
  When it fails, the same agent gets one more try, with the check's output.
  After 2 failed checks in a row, the run stops and asks you.
- **One commit per step.** When the check passes, the script commits that
  agent's changes as `<ticket>: <Agent>`, through the project's git hooks.
  A hook that refuses the commit counts as a failed check. That is how the
  next agent's check can tell its own changes from the last agent's, and it
  is why Implementer-Agent finds the tests already committed.
- **At most 2 returns.** Work goes back to Implementer-Agent at most twice
  per ticket, with the report that sent it back. A third time, the run
  stops and asks you.
- **Nothing leaves your machine.** The script never pushes or merges. Only
  step 8 deploys, to staging, through Build-Agent's own rules.

## Where things are

| Path | What |
| ---- | ---- |
| `ticket/<id>` | The branch the run creates from `main` |
| `.runs/<id>/NN-<agent>.md` | Each agent's report, in order |
| `.runs/<id>/NN-<agent>.check.txt` | The check's output for that step |
| `.runs/<id>/state` | Where the run is. Delete `.runs/<id>` and the branch to start over |

`.runs/` and `agent-report.md` are kept out of git through `.git/info/exclude`.

## Run it

With Claude Code, in the project:

```text
Run ticket ITEM-12.
```

By hand, or from any other tool:

```sh
.agents/flow/ticket.sh start ITEM-12
```

Start the agent it names with the prompt it prints. When the agent is done:

```sh
.agents/flow/ticket.sh done
```

Repeat until it prints `DONE` or `ASK`. `ticket.sh next` prints the current
step again, and `ticket.sh status` shows the whole run.
