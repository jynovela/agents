# Set up test accounts and a components page for reviewing screens

Every screen has states that are hard to see by clicking around: empty,
loading, error, and the odd cases, like a user whose payment failed. They are
where most UI bugs hide, and they rarely get reviewed. This setup lets you see
each one live, on a preview of the real app, without faking anything by hand.

| Piece | What it does |
| ----- | ------------ |
| Test accounts | Fake users, each stuck in one state, created by a seed script in a non-production database |
| Simulate switch | A preview-only setting, like `?simulate=error`, that fakes states data can't produce |
| Components page | A hidden page, like `/dev/components`, that shows every shared component in every state |

Design-Agent names the test account or switch that shows each state in its
screen specs. Planner-Agent turns new ones into tickets. Test-Agent can log in
as them in acceptance tests.

## 1. Test accounts

A test account is a fake user whose data puts them in exactly one state. Give
each a short name that says the state, like `student-new`,
`student-failed-exam`, or `owner-no-items`.

1. **List them in one file**, like `docs/test-accounts.md`: name, the state it
   shows, and how to log in. Use fake names and `@example.invalid` emails.
   Passwords for test accounts go in your secret store, not the file.
2. **Create them with a seed script** that the dev environment runs, like
   `dev/seed-test-accounts.sh`. It must be safe to run twice: delete and
   recreate the test accounts, nothing else.
3. **Run it only outside production.** Locally, and on staging (see
   [build.md](build.md)). The script must refuse to run when it's pointed at
   the production database. Check the database URL or an environment name,
   and exit with an error.

## 2. Simulate switch

Some states come from the system, not the data: slow loading, a server
error, a timeout. A simulate switch makes the app fake them on request.

- Read it from a URL parameter or a cookie, like `?simulate=slow`,
  `?simulate=error`, or `?simulate=empty`.
- Honor it only when the app runs locally or as a preview. In production,
  ignore it completely.
- Keep the list of values short and written down next to the test accounts.

## 3. Components page

One page that shows every shared component from `design/system.md` in every
state, stacked: each button variant normal, focused, disabled, and loading;
each input empty, filled, and with an error; alerts, empty states, dialogs.

- Build it from the real components, so it can't drift from them.
- Return "not found" in production.
- Add each new shared component to it in the same change that adds the
  component.

## 4. Guard production

Both the switch and the components page must be impossible to reach in
production. Add an acceptance test for each that runs against a production
build and expects the switch to do nothing and the page to return 404. Seed
scripts must refuse the production database (step 1).

## 5. Fill in AGENTS.md

In the **Dev environment** section, set:

- `Test accounts:` the file that lists them, like `docs/test-accounts.md`
- `Simulate switch:` how to use it, like `?simulate=slow|error|empty, preview only`
- `Components page:` its path, like `/dev/components, preview only`

Leave `None` for any piece you don't have yet. Design-Agent then marks the
states it can't show yet as needing a new test account, and Planner-Agent
writes tickets for them.

## Steps for the agent

When asked to set this up, do these in order, and ask before anything that
changes hosting settings or a database other than local:

1. Read `AGENTS.md`, `design/system.md` if it exists, and every screen spec in
   `design/screens/`. List each `Shown by:` value.
2. Write `docs/test-accounts.md` with one row per test account the specs
   need.
3. Write the seed script and make it refuse a production database. Run it
   locally twice and show it succeeds both times.
4. Add the simulate switch and the components page, preview only, with the
   acceptance tests from step 4.
5. Fill in the three lines in `AGENTS.md`.
6. End with what you did, what failed, and what the user still needs to do.
