---
name: drive-web-page
description: Read and control a web page showing on a Tarvis device's screen — click buttons, fill fields, navigate to a section, search a site, work through a form. Use when the user wants you to interact with a casted page rather than just display it, or asks what a page currently shows. Triggers on "click the X on the screen", "search for Y on that page", "scroll to the Z section", "log into this site on the TV", "what does the dashboard say right now", "fill in that form". Requires a url cast to already be running, or start one first.
---

# Drive a web page on the screen

When a `url` is casting, the device holds a real browser tab you can read and
act on. This is the loop:

```
cast_content(url) → page_snapshot → act by node id → page_snapshot → …
```

## Read before acting

`page_snapshot` returns the page's accessibility tree: every link, button,
field, and heading with a `role`, a `name`, and a `backendDOMNodeId`. Work from
this, not from screenshots — it's text you can reason over, and the ids are what
the action tools take.

The default view drops empty layout nodes. Pass `raw: true` only if something
you expect is genuinely missing.

Large pages return thousands of nodes. Filter for what you need — role
`button`/`link`/`textbox` and a matching `name` — rather than reading it all.

## Act by node id

- **`page_click`** with `backend_node_id` — finds the element's real position
  itself, so it keeps working when the page shifts or scrolls.
- **`page_type`** with `text`, plus `enter: true` to submit. Click the field
  first; typing goes to whatever has focus.
- **`page_input`** — raw pointer/wheel/key events with 0-1 fractional
  coordinates. An escape hatch for hovers, drags, and keys like Tab or Escape.
  Reach for it only when the two above can't express the gesture.

**Always re-snapshot after anything that changes the page.** Node ids are not
stable across navigations, and acting on a stale id clicks the wrong thing.

Never invent a node id. If the element you want isn't in the snapshot, scroll
with `cast_scroll` and snapshot again, or reconsider whether the page has
loaded.

## Stop at these, every time

Do not attempt, and do not ask the user to give you the values for:

- passwords, passphrases, PINs
- card numbers, bank details
- one-time codes and 2FA prompts
- captchas or "prove you're human" challenges

Hand off instead. Tell the user to open **`<device>/admin`** and use the cast
control there: it shows a live interactive preview of the very same tab, where
they can click and type themselves. When they say they're done, `page_snapshot`
again and carry on from the new state. The session is preserved — you are not
starting over.

This is the intended design, not a limitation to work around. Say plainly what
you need them to do and why.

## Seeing what text can't describe

`page_screenshot` captures the tab as an image. Use it for charts, visual
layout questions, or "does this look right" — not as a substitute for
`page_snapshot` when deciding what to click.

## If there's no page

The page tools report that no web page is casting on that screen. Start one
with `cast_content` and `content_type: url`, then snapshot.
