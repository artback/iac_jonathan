# Shared Telegram UI kit for the homelab bots.
#
# CANONICAL COPY. Do not edit this block inside a pack template — edit here and
# run scripts/sync-bot-ui.sh, which replaces the region between the marker
# comments in every bot that opts in. nomad-pack has no cross-pack include, so
# the alternative is drift between six bots that should look identical.
#
# Nested lists MUST be written with a space between the brackets. nomad-pack
# treats a doubled opening bracket anywhere in a .tpl as its own delimiter, and
# inline keyboards are lists of lists — the exact shape that has broken packs
# here before.

OK, WARN, BAD = "✅", "⚠️", "❌"


def tg(method, payload):
    """Call the Telegram Bot API. Never raises: a bot that dies on a transient
    API blip is worse than one that logs and carries on."""
    import json, urllib.request
    body = json.dumps(payload).encode()
    req = urllib.request.Request("https://api.telegram.org/bot" + TOKEN + "/" + method,
                                 data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except Exception as e:
        print("tg " + method + " failed: " + str(e)[:120], flush=True)
        return {}


def esc(t):
    return str(t).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def bar(pct, width=10):
    """A ten-cell meter reads faster than a number on a phone screen."""
    pct = max(0.0, min(100.0, float(pct)))
    filled = int(round(pct / 100 * width))
    return "█" * filled + "░" * (width - filled)


def dot(pct, warn=75, bad=90):
    return OK if pct < warn else (WARN if pct < bad else BAD)


def ago(seconds):
    if seconds < 90:
        return str(int(seconds)) + "s ago"
    if seconds < 5400:
        return str(int(seconds // 60)) + "m ago"
    if seconds < 172800:
        return str(int(seconds // 3600)) + "h ago"
    return str(int(seconds // 86400)) + "d ago"


def human(n):
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024:
            return str(round(n, 1)) + unit
        n /= 1024
    return str(round(n, 1)) + "PB"


def kb(rows):
    return {"inline_keyboard": rows}


def back_row(target="menu"):
    return [ {"text": "← Menu", "callback_data": target} ]


def card(chat, text, markup, message_id=None):
    """Edit in place when we can. One tidy card beats a wall of near-identical
    replies scrolling up the chat, which is the whole point on a phone."""
    payload = {"chat_id": chat, "text": text, "parse_mode": "HTML",
               "disable_web_page_preview": True, "reply_markup": markup}
    if message_id:
        payload["message_id"] = message_id
        return tg("editMessageText", payload)
    return tg("sendMessage", payload)
