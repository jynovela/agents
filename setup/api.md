# Set up API spec checks

An API is hard to change once clients use it. Removing or renaming a field
breaks their code, and a model making a change won't stop to ask unless
something makes it. This setup puts a gate on the spec: any change that isn't
purely additive fails until a person approves it in a file they commit.

| Piece | File to copy | What it does |
| ----- | ------------ | ------------ |
| Spec diff | `.agents/shared/spec-diff.sh` | Compares the spec with the base branch and fails on any change that isn't additive, unless `.api/approved.md` lists it |
| Approvals | `.api/approved.md` (you create it) | One line per breaking change a person approved |
| Style rules | `setup/spectral.yaml` | Spectral ruleset: path naming, field casing, error responses, timestamps |
| Guidelines | `setup/api-guidelines.md` | The same rules in prose, plus the ones a linter can't check |
| Pre-commit hook | `setup/githooks/pre-commit` | Runs spec lint and the spec diff before each commit |
| Lint guard | `.agents/shared/lint-guard.sh` | Fails when an agent edits `.spectral.yaml` or `.api/approved.md` |

The diff tool is [oasdiff](https://github.com/oasdiff/oasdiff). Spec lint is
[Spectral](https://github.com/stoplightio/spectral). Tested with oasdiff
1.39.0 and Spectral 6.17. This guide covers OpenAPI specs only.

## Let Claude do it

In Claude Code, from the project root, say:

```text
Set up API spec checks. Read setup/api.md and follow "Steps for the agent" in order.
```

The steps below are written for an agent to follow. Each one ends with
something to tell you, and it stops to ask where a choice is yours.

## Steps for the agent

Do every step in order. Don't edit source code or tests in any step, and
don't edit the spec except for the test in step 9, which you undo. Keep a list of what you did and found; you report it in step 10.

1. **Find the spec.** Run
   `git ls-files '*openapi*' '*swagger*' '*.graphql' '*.proto'`.
   - One or more OpenAPI files (`.yaml`, `.yml`, `.json`): note their paths
     and go on.
   - Only GraphQL or protobuf files: stop. Tell the person this setup covers
     OpenAPI only.
   - Nothing: stop. Ask the person whether the project has an HTTP API and
     where its spec should live. Don't write a spec yourself.

2. **Ask how the spec is kept.** Look for a command that generates the spec
   from code (for example FastAPI's `app.openapi()`, a `springdoc` plugin, or
   a `make openapi` target). Then ask the person which one fits, and say
   which you think it is and why:
   - `generated from code`: a command writes the spec. Ask for the command.
   - `follows the code`: people edit the spec by hand to match the code.
   - `the contract`: the spec comes first and the code must match it.

   Wait for the answer before step 6.

3. **Check the tools.** Run `oasdiff --version` and
   `npx --yes @stoplight/spectral-cli@6 --version`.
   - If `oasdiff` is missing, ask the person to run `brew install oasdiff`
     (or `go install github.com/oasdiff/oasdiff@v1.39.0`). Don't install
     packages yourself.
   - If `npx` is missing, ask the person to install Node.js.
   - Check again from the shell your agents use. Hermes may not see
     Homebrew's folder on the `PATH`; if `oasdiff` is installed but not
     found there, tell the person.

4. **Add the style rules.** Copy `setup/spectral.yaml` to `.spectral.yaml`
   in the project root. Find the field casing the spec already uses:
   `grep -nE '^ +[a-z]+_[a-z_]+:' <spec>` finds snake_case fields, and
   `grep -nE '^ +[a-z]+[A-Z][A-Za-z]*:' <spec>` finds camelCase ones. Set
   `type:` under `property-casing` to the one with more hits (`snake` or
   `camel`). If both are common, keep `camel` and tell the person.

5. **Add the guidelines.** Copy `setup/api-guidelines.md` to
   `docs/api-guidelines.md`. Fill in each `TAILOR` comment from what the spec
   already does: casing from step 4, the pagination parameters it uses, its
   error shape. If the spec doesn't show an answer, leave the comment and
   list it for the person.

6. **Create the approvals file.** Create `.api/approved.md` with exactly this
   content:

   ```markdown
   # Approved API changes

   One line per breaking change a person approved:
   `- <METHOD> <path> <change-id> (<ticket>)`. Copy the method, path, and
   change id from the spec-diff output. Only people edit this file.
   ```

7. **Fill in AGENTS.md.** Under **Commands**, add these lines, with your
   spec path in place of `openapi.yaml` and your base branch in place of
   `main`:

   ```markdown
   - API spec is: follows the code
   - Lint API spec: `npx --yes @stoplight/spectral-cli@6 lint --fail-severity error openapi.yaml`
   - Spec diff: `.agents/shared/spec-diff.sh main`
   ```

   Use the answer from step 2 on the first line. For `generated from code`,
   write `generated from code by <command>`. If there's more than one spec
   file, set `SPECS` at the top of `.agents/shared/spec-diff.sh` to all of
   them, separated by spaces.

8. **Turn on the pre-commit hook steps.** If `.githooks/pre-commit` exists,
   set `SPEC_LINT` and `SPEC_DIFF` at its top to the same two commands as in
   step 7. If it doesn't exist, tell the person to set up the hook from
   `setup/lint.md` first, and skip this step.

9. **Run both checks and prove the gate works.**
   1. Run the "Lint API spec" command. Errors mean the spec is invalid: list
      each one with its line for the person. Don't fix them. Count the
      warnings, and don't fix them either: they're on endpoints that already
      shipped.
   2. Run `.agents/shared/spec-diff.sh main`. It should pass.
   3. Prove it catches a breaking change. In the spec, rename one response
      field (for example `name:` to `title:`), run the spec diff again, and
      check that it prints `NEEDS APPROVAL` and fails. Then undo it with
      `git restore <spec>`, and run `git diff --stat -- <spec>` to confirm
      the spec is unchanged.

10. **Report.** Tell the person, in this order:
    - The spec files and the mode from step 2.
    - The tool versions, and anything they need to install.
    - The files you created or changed.
    - Spec lint: the number of errors (each with its line) and warnings.
    - Whether the spec diff passed, and whether the gate caught the test
      rename.
    - `TAILOR` comments you couldn't fill in.
    - The CI step below, for whoever owns the CI workflow.
    - That they should commit the new files themselves with
      `git commit --no-verify`. The lint guard blocks changes to
      `.spectral.yaml`, `.api/`, and `.githooks/` so agents can't loosen
      them, and that includes this first commit. Don't commit for them.

## Approve a breaking change

When the spec diff fails, it prints one line per change, like:

```text
NEEDS APPROVAL  GET /items response-optional-property-removed: removed the optional property 'items/items/name' ...
```

If you accept the break, add a line to `.api/approved.md` and commit it
yourself, with `git commit --no-verify` (the lint guard blocks changes to that
file, so agents can't approve their own changes):

```markdown
- GET /items response-optional-property-removed (ITEM-14)
```

A line approves that kind of change on that endpoint. Use `*` for the method
or path when the output shows `*`. Approval written anywhere else, such as in
a ticket, a PR, or a code comment, doesn't count.

The gate treats more changes as breaking than `oasdiff breaking` does. It
also stops on removing an optional response field, changing a default, and
deprecating an endpoint, because clients can depend on all of those.

## Run it in CI

Add these steps to the pull request workflow. The `fetch-depth: 0` line lets
the check find the base branch. Don't add `continue-on-error`: a red spec
diff means an unapproved breaking change.

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-go@v5
        with:
          go-version: stable
      - run: go install github.com/oasdiff/oasdiff@v1.39.0
      - run: npx --yes @stoplight/spectral-cli@6 lint --fail-severity error openapi.yaml
      - run: PATH="$PATH:$HOME/go/bin" .agents/shared/spec-diff.sh origin/${{ github.base_ref }}
```

The CI steps are untested; the local commands above are tested.

## What this doesn't cover

- Interface changes with no spec: CLI flags, environment variables, and code
  that changes a response without touching the spec. The API-Agent checks
  those.
- Database schema and migrations.
- GraphQL and protobuf. The same idea works with their diff tools
  (`graphql-inspector diff`, `buf breaking`).
