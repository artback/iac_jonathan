# Librarianbot Nomad Pack

Telegram bot that files things into Calibre-Web, so they reach the Kindle
through the OPDS catalogue KOReader already points at.

- **Send a link** → fetches the page, strips navigation/ads/scripts, builds a
  valid EPUB 3 and uploads it. Pages with under 120 words of prose are
  refused (paywall or JS-rendered) rather than uploaded empty.
- **Send an ebook** (epub/pdf/mobi/azw3/cbz/fb2/txt) → straight into the library.

Outbound only: long-polls Telegram, talks to Calibre-Web over HTTPS. Nothing
listens, nothing is exposed.

## Why a session, not an API

Calibre-Web has no upload API, so the bot drives the same login + multipart
form a browser would (CSRF token included). A stale session is dropped on
error so the next message re-authenticates.

**Uploads must be enabled** in Calibre-Web: Admin → Basic Configuration →
Feature Configuration → Enable Uploads, plus the upload permission on the
user. Without it `/upload` returns 400 and no form is rendered.

## Secrets (gitignored `vars/librarianbot.hcl`)

```hcl
telegram_token   = "..."   # its own bot; one process per token
calibre_user     = "..."
calibre_password = "..."
```

Deploy: `nomad-pack run packs/librarianbot -f vars/librarianbot.hcl`

## Article extraction

Dependency-free heuristic: keep block-level prose (p/h1-h4/li/blockquote/pre),
drop script/style/nav/footer/aside/header/form/iframe. Good on ordinary
article layouts (12k words extracted cleanly from a Wikipedia page in
testing), poor on JavaScript-rendered sites — which the word-count guard
catches rather than silently producing an empty book.
