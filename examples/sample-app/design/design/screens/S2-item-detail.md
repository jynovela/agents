# S2 Item detail

Flows: edit-item (F2, F3)

## Purpose

See one item and change its name or price.

## Reached from

- S1 Item list: tap an item row

## Content

- Name field
- Price field: PriceInput (`web/components.js:16`)

## Actions

- Primary: "Save" -> S1
- "Back" -> S1

## States

- Empty: Not applicable: the screen always opens from one item
- Loading: fields show gray placeholders until the item loads; "Save" shows "Saving..." while it saves
- Error: name empty or price not a number: a message under the field says how to fix it; entered values stay
- Success: goes to S1 with "Item saved"

## Copy

- Title: the item's name
- Button: "Save"

## Accessibility

- Field labels "Name" and "Price" stay visible above the fields

## Open questions

- None
