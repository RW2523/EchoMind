# Wiki pages (staged)

These are the GitHub Wiki pages, kept in the repo so they're versioned and reviewable.
They mirror the canonical docs in [`docs/`](../docs/): `Home.md` ↔ `README.md`,
`User-Guide.md` ↔ `docs/USER_MANUAL.md`, `Architecture.md` ↔ `docs/ARCHITECTURE.md`,
`FAQ.md` ↔ `docs/FAQ.md`.

## Publishing

The repo is public and *Settings ▸ Features ▸ Wikis* is enabled. GitHub only creates the
wiki's backing git repo after the **first page is created via the web UI**, so:

1. Open <https://github.com/RW2523/EchoMind/wiki> → **Create the first page** → Save
   (any content — the publish script overwrites it).
2. Run `./wiki/publish_wiki.sh` to push all staged pages.

To update later, just edit the files here and re-run `./wiki/publish_wiki.sh`.
