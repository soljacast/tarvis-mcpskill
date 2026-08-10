---
name: cast-to-screen
description: Put content on a physical screen attached to a Tarvis device — a web page, dashboard, video, YouTube clip, image, PDF, slide deck, document, audio, or a block of text. Use when the user asks to show, cast, display, put up, or play something on a screen, TV, monitor, or "the big screen". Triggers on "show X on the screen", "cast this deck", "put the dashboard up", "play this video on the TV", "display these photos". Also use to stop a cast, scroll or zoom what's showing, or page through a document.
---

# Cast to a screen

A Tarvis device drives one or more physical screens over HDMI. You show content
by calling `cast_content` or `cast_file`; the device renders it fullscreen.

## Start here

Call `device_status` first if you don't already know how many screens exist or
what's on them. Screens are numbered from 1. Screen 1 is the default.

## Choosing the tool

**`cast_content`** — for anything already reachable at a URL, or for text you
write yourself. Pass `content_type` plus `content`:

| content_type | content is | use for |
|---|---|---|
| `url` | a web address | dashboards, docs, any live page |
| `youtube` | a YouTube URL | YouTube playback |
| `video` | a video URL | MP4/MOV/MKV over the network |
| `image` | an image URL | photos, charts |
| `pdf_image` | a PDF URL | documents, decks |
| `text` | the text itself | messages, countdowns, status lines |
| `html` | an HTML document | custom layouts, charts you generate |
| `audio` | an audio URL | music, recordings |

**`cast_file`** — for a file on the machine you're running on. Read it, base64
it, pass `filename` and `data`. PowerPoint and Word files are converted to PDF
automatically, so they page through like a deck. Files over 8 MB should go
through the device's `/api/agent/v1/cast/upload` route instead.

Give every cast a short `title` — it's what the device shows while loading and
what `device_status` reports back.

## Controlling what's showing

- `cast_scroll` — direction plus optional pixel `amount` (default 100)
- `cast_zoom` — `in`, `out`, or `reset`
- `cast_page` — a `page` number, or `direction: next`/`prev` for PDFs and decks
- `cast_playback` — `play`, `pause`, `toggle` for video and audio
- `cast_stop` — one screen, or omit `screen` to clear them all

Prefer these over re-casting. Re-casting reloads the content and loses position.

## Camera and screen share: hand it to a person

You have no camera and no screen of your own, and a browser will not start
either without a deliberate click from the person sitting at it. There is no
tool for these — build a link and hand it over:

```
<device>/cast?source=camera&screen=1
<device>/cast?source=screen_share&screen=1
```

`<device>` is the same base URL you use for everything else. The link resolves
itself: if casting is admin-only on that device, or events are on without cast
enabled, it forwards to the admin panel and asks for a password first. Either
way the person lands on the right card for the right screen and clicks once.

Check `device_status` for how many screens exist before naming one — plenty of
devices have only screen 1, and a link to a screen that is not there wastes
the person's time.

Open it for them when you can — `open <url>` on macOS, `xdg-open` on Linux,
`start` on Windows — so the only thing left is the click. Otherwise print the
link. For a phone camera, the link is what to put in front of them.

Then **poll `cast_status`**: when they go live, that screen's `content_type`
becomes `camera` or `screen_share`. That is how you know it worked; do not
claim it did until you see it. If nothing changes after a while, ask rather
than retry — they may still be choosing a window, or may have declined.

Expect one thing you cannot remove: the screen-share picker always needs a
click. Say so plainly instead of implying it will happen by itself.

## Web pages are special

A `url` cast opens as a real fullscreen browser tab on the device, not an
embedded frame — so pages that refuse to be framed still work. It also means
you can *read and drive* that page afterwards. If the user wants you to interact
with the page rather than just display it, that's the **drive-web-page** skill.

One thing that confuses people: while a `url` is casting, the device's own
`/splash` page shows a small "Casting web page" placeholder. That's expected —
the real page is the browser tab in front of it, not a bug.

## Checking your work

`screen_screenshot` shows what a screen is actually displaying. Use it when a
cast might have failed, or when the user asks how something looks. For reading
a web page's contents, `page_snapshot` is far cheaper and more useful.

## When there's no session

Cast tools need an active session on the device. If they report no active
session, tell the user to open the device's admin page and start or select one
— you can't create it for them.
