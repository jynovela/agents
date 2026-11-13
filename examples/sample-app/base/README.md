# itemctl

A command-line tool that lists items from the inventory service.

## Quickstart

Requires: Python 3.9 or later.

1. Point the tool at your inventory service:

   ```sh
   export ITEMCTL_API_URL="http://localhost:8000"
   ```

2. List the first five items:

   ```sh
   python app.py list --max 5
   ```

   Expected output: one line per item, with the item ID and name separated by
   a tab.

See [docs/usage.md](docs/usage.md) for all options.
