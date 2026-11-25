# Set up a project for the agents

`install.sh` copies this folder into a project as `.agents/setup/`. It holds
the setup guides, and the files they tell you to copy.

Run `.agents/shared/doctor.sh` to see which agents still need something.
Each "NOT READY" line names the `AGENTS.md` line to set, the tool to
install, and the guide here to follow.

## What to set up

Agents can only check what they can run. Do these once per project, or the
Test-Agent falls back to unit tests and its report says the criteria are
untested.

1. **A dev environment agents can drive.** Fill in the "Dev environment"
   section of `AGENTS.md` with exact commands: start the app (returning once
   it's healthy), stop it, a health check, the base URL, reset test data, a
   read-only database query, tail the logs, trigger jobs, and the unit and
   acceptance test commands. Use a throwaway local database with seed data,
   never a shared or production one. Write logs to a file agents can tail.
   `examples/sample-app/base/dev/` in the agents repo shows small scripts
   for each command.
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
   [lint.md](lint.md): a linter config, a pre-commit hook, a
   Claude Code hook that lints each edited file, and CI. Fill in "Lint code"
   and "Fix lint" in `AGENTS.md`. Most style and safety rules belong there,
   not in prose.
6. **Secret scanning that agents can't skip.** Follow
   [security.md](security.md): gitleaks with a config, a scan in
   the pre-commit hook and in CI, and the "Scan secrets" command in
   `AGENTS.md`. The role check scripts also use gitleaks when it's on the
   `PATH`.
7. **A gate on API changes, if the project has an HTTP API.** Follow
   [api.md](api.md): a check that fails on any spec change that
   isn't additive until you approve it in `.api/approved.md`, Spectral style
   rules, and API guidelines. Fill in "API spec is", "Lint API spec", and
   "Spec diff" in `AGENTS.md`.
8. **Staging, and a production only you can deploy.** Follow
   [build.md](build.md): a local, staging, and production
   environment, a deploy script with no production target, a build guard,
   one CI workflow that runs the `AGENTS.md` commands, and a Claude Code hook
   that blocks production commands. Most important: keep production
   credentials off the machine agents run on.
9. **A way to see every screen state live, if the project has a UI.** Follow
   [demo-data.md](demo-data.md): test accounts that each show
   one state, a preview-only switch that fakes slow or failing requests, and
   a hidden page with every shared component. Fill in "Test accounts",
   "Simulate switch", and "Components page" in `AGENTS.md`.

## Commit the setup yourself

Agents never commit. Commit the setup files yourself with
`git commit --no-verify`: the lint guard blocks changes to hooks and config,
so agents can't loosen them later.
