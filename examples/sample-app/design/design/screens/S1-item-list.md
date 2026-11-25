# S1 Item list

Flows: edit-item (F1, F4)

## Purpose

See every item in stock and pick one.

## Reached from

- App start
- S2 Item detail: "Save" and "Back"

## Content

- Title "Items"
- One row per item with its name and price: ItemList (`web/components.js:3`)

## Actions

- Primary: Tap an item row -> S2
- "Add an item" -> system: opens the add item page, not designed yet

## States

- Empty: "No items yet" with "Add an item": EmptyState (`web/components.js:12`)
- Loading: three gray placeholder rows
- Error: "Couldn't load your items. Try again." with a "Try again" button
- Success: the list of items; after an edit, "Item saved" shows at the top for 3 seconds

## Copy

- Title: "Items"
- Empty: "No items yet"
- Saved: "Item saved"

## Accessibility

- Each row is one link with the item's name and price read together

## Open questions

- None
