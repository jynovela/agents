// Small UI components for the itemctl web view. Plain JavaScript, no framework.

export function ItemList(items) {
  const rows = items.map((item) => ItemRow(item)).join("");
  return `<ul class="items">${rows}</ul>`;
}

export function ItemRow(item) {
  return `<li><a href="/items/${item.id}">${item.name}</a> <span>${item.price}</span></li>`;
}

export function EmptyState(message, actionLabel, actionHref) {
  return `<div class="empty"><p>${message}</p><a href="${actionHref}">${actionLabel}</a></div>`;
}

export function PriceInput(id, label, value) {
  return `<label for="${id}">${label}</label>
<input id="${id}" name="${id}" inputmode="decimal" value="${value || ""}">
<p class="field-error" id="${id}-error" hidden></p>`;
}

export function ConfirmDialog(title, body, confirmLabel) {
  return `<dialog><h2>${title}</h2><p>${body}</p>
<button value="cancel">Cancel</button> <button value="ok">${confirmLabel}</button></dialog>`;
}
