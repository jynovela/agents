# Set up builds, staging, and deploys for agents

Agents can build and deploy as fast as they write code. That's fine on your
machine and on a staging copy of the app. It's not fine on production, where
a mistake reaches real users and real data. This setup lets agents build,
run, and deploy freely up to staging, and makes production a step only a
person takes.

| Piece | File to copy | What it does |
| ----- | ------------ | ------------ |
| Deploy wrapper | `setup/deploy.sh` to `dev/deploy.sh` | The only way agents deploy. Refuses any target not on the allowed list, logs every attempt to `logs/deploy.log`, and rolls back with one command |
| Build guard | `.agents/checks/build-guard.sh` | Fails when a change makes a failing step pass (`continue-on-error`, `\|\| true`), removes a CI step or check, or adds a production deploy command |
| CI workflow | `setup/ci.yml` to `.github/workflows/ci.yml` | Runs the same commands as `AGENTS.md`, in the same order, on every pull request |
| Production gate | `setup/claude-prod-gate.sh` to `.claude/hooks/prod-gate.sh` | Claude Code hook that blocks production deploy commands before they run |

## 1. Have three environments

| Environment | What it is | Who deploys | Data |
| ----------- | ---------- | ----------- | ---- |
| Local | The app on your machine, started with `dev/start.sh` | Agents, freely | Throwaway seed data |
| Staging | A copy of production on real hosting, for testing before going live | Agents, when the task says so and every check is green | Its own fake data, never a copy of real users |
| Production | What users see | A person, by merging to the production branch | Real |

**Set up staging before your first real users.** Local catches most bugs, but
not the ones that come from real hosting: environment variables, build
settings, database migrations, third-party callbacks, and cold starts. Staging
is where you click through a change before anyone else sees it.

Rules that make staging worth having:

- **Same build.** Staging runs exactly what production will run, built the
  same way. Don't hand-tweak it.
- **Separate data.** Its own database, with fake data. Never point staging at
  the production database, and never copy real user data into it.
- **Separate secrets.** Staging has its own keys. Production keys never leave
  production.
- **Migrations go to staging first.** Every database change runs on staging
  before production.

When you plan a project, add staging to the plan: one setup ticket for the
staging environment, and a "Verify on staging" step before each release. The
Planner-Agent writes criteria against the local dev environment; staging
checks are a release step for you, not ticket criteria.

## 2. Example: staging with Vercel and Supabase

Vercel builds every branch you push as a *preview deployment* with its own
URL, and builds the production branch (usually `main`) as production. That
makes previews a ready-made staging. Supabase holds the database, so
staging needs its own Supabase project.

I couldn't test these steps against live accounts. Check each against the
Vercel and Supabase docs when you set them up.

1. **Two Supabase projects.** Create `<app>-staging` and `<app>-prod`. Use
   staging for every test. Locally, `supabase start` runs a third, throwaway
   database in Docker for agents.
2. **Environment variables by environment.** In Vercel project settings, set
   the Supabase URL and keys for the **Preview** environment to the staging
   project, and for **Production** to the prod project. Then no preview build
   can reach production data, whatever its code does.
3. **Production branch.** In Vercel, keep the production branch as `main`.
   In GitHub, protect `main`: require a pull request and your approval before
   merging. Merging is now your production deploy button.
4. **A stable staging URL (optional).** Keep a long-lived `staging` branch and
   give it its own domain in Vercel, like `staging.<app>.com`. Merge feature
   branches into `staging` to test them together before `main`.
5. **Migrations.** Link the Supabase CLI on your machine to the staging
   project only (`supabase link`, once, by you). Agents then run
   `supabase db push` against staging. Run production migrations yourself, or
   from CI after merge, never from an agent's shell.
6. **No Vercel token for agents.** Agents don't need one: pushing a branch
   creates the preview. A Vercel token can deploy to production too, so keep
   it off the machine agents run on. If you do want `vercel deploy` in
   `dev/deploy.sh`, know that the hook and build guard are the only things
   stopping `--prod`.

Supabase also has database branching, which makes a database per preview. It
may need a paid plan; start with two projects.

## 3. Fence off production

Four layers, strongest first. Only the first two stop a deploy; the other two
catch an agent that tries.

1. **No production credentials where agents run.** No production database
   URL, no host token that can deploy to production, no production cloud keys.
   Check what's in your shell (prints names only, never values):

   ```sh
   env | cut -d= -f1 | grep -Ei 'prod|token|secret|key|supabase|vercel|database'
   ```

   Look at each name it prints and remove anything that reaches production.
2. **Production needs a person.** Production deploys only from the production
   branch, and that branch needs your approval to merge. In GitHub, protect
   `main`, or use an environment named `production` with you as a required
   reviewer if CI deploys.
3. **Agents deploy only through `dev/deploy.sh`**, which has no production
   target.
4. **Hooks and checks.** In Claude Code, the production gate hook blocks
   production commands before they run. For every tool, `build-guard.sh` and
   the Build-Agent's check fail a run that adds one. Hermes has no hooks we've
   confirmed, so on Hermes layers 1 and 2 matter most.

## 4. Add the deploy wrapper

```sh
mkdir -p dev && cp setup/deploy.sh dev/deploy.sh && chmod +x dev/deploy.sh
```

Fill in its `TAILOR` lines: a deploy command and a rollback command for
`local` and `staging`. Never add a production target. Add `logs/` to
`.gitignore`.

Rehearse the rollback now, while nothing is on fire:

```sh
dev/deploy.sh staging
dev/deploy.sh rollback staging
```

A rollback you have never run doesn't count as one.

## 5. Fill in the commands in AGENTS.md

```markdown
- Build: `dev/build.sh`
- Build guard: `.agents/checks/build-guard.sh`
- Deploy (local or staging only): `dev/deploy.sh staging`
- Roll back a deploy: `dev/deploy.sh rollback staging`
```

"Build" is whatever turns the code into what you ship: a bundle, a zip, an
image. Write "None" for a command you don't have yet.

## 6. Add the production gate hook (Claude Code)

```sh
mkdir -p .claude/hooks && cp setup/claude-prod-gate.sh .claude/hooks/prod-gate.sh && chmod +x .claude/hooks/prod-gate.sh
```

Register it in `.claude/settings.json`. If the file already has `hooks`, add
the `PreToolUse` entry to it:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/prod-gate.sh" }
        ]
      }
    ]
  }
}
```

Fill in its `TAILOR` line with your host's production commands. It also
blocks `supabase link`, so only you choose which project the CLI points at.

## 7. Run the same checks in CI

```sh
mkdir -p .github/workflows && cp setup/ci.yml .github/workflows/ci.yml
```

Fill in its `TAILOR` lines with your `AGENTS.md` commands. This is the one
CI workflow for the project: the lint, security, and API guides add their
steps to it. Pin every tool version so a new release doesn't fail every
open pull request.

Every step blocks the merge except the lint guard, which is report-only on
purpose (see `setup/lint.md`). `build-guard.sh` allows `continue-on-error` on
that step only.

## 8. When the build guard fails

It prints `file:line` and what it found. Fix the cause of the failure instead
of the step. If you decide a step really should go, or should stop blocking,
that's your call: commit it yourself, skipping the pre-commit hook. Agents never skip it.
