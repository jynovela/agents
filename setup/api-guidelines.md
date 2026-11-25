# API guidelines

<!-- TAILOR: Copy to docs/api-guidelines.md and change any rule your API
already breaks on purpose. Rules marked (Spectral) are checked by
.spectral.yaml; keep the two in step. -->

These rules apply to endpoints you add or change. Don't change a shipped
endpoint just to follow them: renaming or reshaping it breaks every client
that uses it. List the mismatch instead.

## Don't break clients

- Add, don't change. New endpoints, new optional fields, and new optional
  parameters are safe. Removing, renaming, retyping, or making something
  required is a breaking change and needs a person's approval in
  `.api/approved.md`. `.agents/shared/spec-diff.sh` enforces this.
- Clients must ignore response fields they don't know, so adding a field is
  never breaking.
- To remove something, mark it `deprecated: true` first and say what replaces
  it. Remove it only after clients have moved, with approval.
- No version prefix like `/v1/` unless this project opts in. Versioning is a
  last resort: it doubles what you maintain.
  <!-- TAILOR: if you version, say how (path, header) and when a new version is allowed. -->

## Paths and methods

- Paths name resources with plural nouns: `GET /orders`, not
  `GET /getOrders`. (Spectral)
- Lowercase kebab-case segments: `/order-items`. (Spectral)
- At most two resource levels: `/users/{id}/orders`. Filter deeper with query
  parameters. (Spectral)
- `GET` reads, `POST` creates, `PUT` replaces, `PATCH` updates part, `DELETE`
  removes. `GET` never changes data.

## Requests and responses

- JSON in and out.
- One field casing everywhere: the casing the spec already uses. (Spectral)
  <!-- TAILOR: camelCase or snake_case. -->
- Responses are objects, never a bare array or value, so fields can be added
  later: `{"items": [...]}`. (Spectral)
- Timestamps in ISO 8601 with `format: date-time`:
  `2026-01-12T14:07:17Z`. (Spectral)
- Don't expose internal details: stack traces, SQL, internal IDs nobody
  needs.

## Errors

- Use the status code that fits: `400` bad input, `401` no or bad
  credentials, `403` not allowed, `404` not found, `409` conflict, `422`
  valid shape but rejected, `429` rate limited. Never `200` with an error
  body.
- Every operation documents its 4xx responses. (Spectral)
- One error shape for the whole API.
  <!-- TAILOR: your error shape, for example {"error": "<message>"}. -->

## Lists

- One pagination style for the whole API.
  <!-- TAILOR: limit and offset, or cursor. -->
- Use a cursor for any list that can grow past a few thousand rows. Offset
  gets slower with every page, and switching later is a breaking change.

## Writes and auth

- Create operations that take real action (payments, messages) accept an
  optional idempotency key, so clients can retry safely.
- Auth is declared in `components.securitySchemes`. (Spectral)

Rate limits, transport security, and authorization rules belong to the
security setup (`setup/security.md`), not here.
