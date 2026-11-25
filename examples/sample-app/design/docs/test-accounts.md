# Test accounts

Fake shop owners for reviewing the web view. The seed creates them in the
local database only. Passwords are in the team's secret store.

| Account | State it shows | Log in as |
| ------- | -------------- | --------- |
| `owner-no-items` | A shop with no items: every list is empty | `owner-no-items@example.invalid` |
| `owner-three-items` | A shop with three items, one of each in stock | `owner-three-items@example.invalid` |

Simulate switch values: `?simulate=slow` (every request takes 3 seconds),
`?simulate=error` (every request fails with a server error).
