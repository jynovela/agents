# Run the agents in Hermes, one profile each

This sets up one [Hermes](https://github.com/NousResearch/hermes-agent)
profile per agent. Each profile has its own `SOUL.md` and its own model, so
you can run most agents on a cheap local model and keep a strong model for
the ones that need it.

Status: checked against the Hermes docs, not yet run on a real Hermes
install. If a command below fails, the text it prints is what to report.

## How it fits together

| Piece | Where it lives | What it holds |
| ----- | -------------- | ------------- |
| The profile | `~/.hermes/profiles/<name>/` | `SOUL.md`, the model, your keys, and that agent's sessions |
| `SOUL.md` | In the profile | About 30 lines: who the agent is, and "read `AGENTS.md` and your `SKILL.md` in this folder first" |
| The instructions | In each project, `.agents/skills/<name>/SKILL.md` | The full role. Hermes and Claude Code read the same file |

`SOUL.md` is thin on purpose. The role text stays in one place, in the
project, so a profile never goes stale when an agent changes. Hermes loads
`SOUL.md` only from the profile, and loads `AGENTS.md` from the folder you
start it in.

## Before you start

- Hermes is installed, and your default profile already works with a model.
  The new profiles copy its model, provider, and keys.
- This repo is cloned. The steps below assume `~/agents`.
- The agents are installed in your project. See the README.

## Set up the profiles

1. Create a profile for every agent:

   ```sh
   cd ~/agents
   git pull
   hermes/profiles.sh all
   ```

   Or only some:

   ```sh
   hermes/profiles.sh docs-agent test-agent
   ```

2. Check that they exist:

   ```sh
   hermes profile list
   ```

Running the script again is safe. It keeps a profile that exists, with its
model and history, and only replaces its `SOUL.md`.

### By hand, for one agent

The script does only this, so you can do it yourself. For Docs-Agent:

```sh
hermes profile create docs-agent --clone
cp ~/agents/agents/docs-agent/hermes/SOUL.md ~/.hermes/profiles/docs-agent/SOUL.md
```

To write the `SOUL.md` yourself, this is all it needs to say:

```text
You are Docs-Agent. Before anything else, read AGENTS.md in the current
folder, then read .agents/skills/docs-agent/SKILL.md, and follow both
exactly. If either is missing, stop and say so.
```

## Run an agent

Start it inside the project's root folder. Hermes reads `AGENTS.md` from the
folder it starts in.

```sh
cd /path/to/your/project
docs-agent chat
```

Then give it the task:

```text
Update the docs for this branch against main.
```

`docs-agent chat` is the same as `hermes -p docs-agent chat`. If your shell
doesn't find `docs-agent`, use the long form.

## Choose a model per agent

Each profile keeps its own model. Change one without touching the others:

```sh
hermes -p review-agent config set model.default <model name>
```

See what each profile uses:

```sh
hermes profile list
```

A starting point, from the test runs in this repo:

| Agent | Model |
| ----- | ----- |
| Review-Agent | Your strongest model, and a different family than the one that writes the code |
| Security-Agent | A small model for routine changes. Your strongest for auth, file handling, and new endpoints |
| Planner-Agent | A strong model. Its tickets decide everything after it |
| The others | A small local model. Their check scripts catch most mistakes |

## Things to know

- **Don't add a `.hermes.md` file to the project.** Hermes loads only one
  project file, and `.hermes.md` wins over `AGENTS.md`.
- **A profile is not a sandbox.** `SOUL.md` guides the model. It doesn't
  stop it from using a tool. The check script in each agent's folder is
  what fails a run that broke a rule, so run it after every agent:
  `.agents/skills/<name>/check.sh`.
- **The new profiles copy your default profile's memory files.** Each
  `SOUL.md` tells the agent not to treat memory as fact. To remove the copy,
  delete `MEMORY.md` and `USER.md` in `~/.hermes/profiles/<name>/memories/`.
- **The two skills have no profile.** `user-flows` and `design-system` are
  procedures any agent can run. In the project, run `hermes skills trust`
  once, and Hermes loads them from `.agents/skills/`.
- **To remove a profile:** `hermes profile delete <name>`.
