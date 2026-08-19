job "mediabot" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "mediabot-group" {
    count = 1

    task "bot" {
      driver = "docker"

      config {
        image   = "python:3.12-alpine"
        command = "python"
        args    = ["/local/bot.py"]
        mounts = [
          {
            type   = "bind"
            source = "local/bot.py"
            target = "/local/bot.py"
          }
        ]
      }

      template {
        destination = "secrets/bot.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
          TELEGRAM_TOKEN="{{ with nomadVar "nomad/jobs/mediabot" }}{{ .telegram_token }}{{ end }}"
          ALLOWED_CHAT_IDS="[[ var "allowed_chat_ids" . ]]"
          RADARR_URL="[[ var "radarr_url" . ]]"
          RADARR_KEY="{{ with nomadVar "nomad/jobs/mediabot" }}{{ .radarr_api_key }}{{ end }}"
          SONARR_URL="[[ var "sonarr_url" . ]]"
          SONARR_KEY="{{ with nomadVar "nomad/jobs/mediabot" }}{{ .sonarr_api_key }}{{ end }}"
        EOH
      }

      # Outbound long-polling only — nothing exposed. Search results use
      # inline keyboards; adds run with the instance's first quality
      # profile and root folder, and trigger an immediate release search.
      template {
        destination = "local/bot.py"
        change_mode = "restart"
        data        = <<EOH
import json, os, re, time, urllib.request, urllib.parse

TOKEN = os.environ["TELEGRAM_TOKEN"]
API = "https://api.telegram.org/bot" + TOKEN

# --- BEGIN SHARED UI (managed by scripts/sync-bot-ui.sh) ---
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
# --- END SHARED UI ---

ALLOWED = {s.strip() for s in os.environ.get("ALLOWED_CHAT_IDS", "").split(",") if s.strip()}
ARR = {
    "m": {"url": os.environ["RADARR_URL"], "key": os.environ["RADARR_KEY"],
          "kind": "movie", "icon": "🎬"},
    "s": {"url": os.environ["SONARR_URL"], "key": os.environ["SONARR_KEY"],
          "kind": "series", "icon": "📺"},
}

def tg(method, payload):
    req = urllib.request.Request(API + "/" + method,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=70) as r:
        return json.load(r)

# Browsing happens in the shared group, so search results land silently and
# tidy themselves up once a choice is made. Everything stays in one thread —
# splitting it across a DM was more confusing than the noise it saved.
CARDS = {}   # chat -> result-card message ids still awaiting a choice

def say(chat, text, keyboard=None, silent=False):
    p = {"chat_id": chat, "text": text, "disable_notification": silent}
    if keyboard:
        p["reply_markup"] = {"inline_keyboard": keyboard}
    try:
        return tg("sendMessage", p).get("result", {}).get("message_id")
    except Exception as e:
        print("say error:", e, flush=True)
        return None

def forget_cards(chat):
    """Remove the result cards once one has been chosen."""
    for mid in CARDS.pop(str(chat), []):
        try:
            tg("deleteMessage", {"chat_id": chat, "message_id": mid})
        except Exception:
            pass   # older than 48h, or already gone

def arr_get(a, path):
    req = urllib.request.Request(a["url"] + "/api/v3" + path,
                                 headers={"X-Api-Key": a["key"]})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def arr_post(a, path, payload):
    req = urllib.request.Request(a["url"] + "/api/v3" + path,
        data=json.dumps(payload).encode(),
        headers={"X-Api-Key": a["key"], "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)

def photo_card(chat, photo, caption, keyboard, silent=True):
    p = {"chat_id": chat, "photo": photo, "caption": caption,
         "disable_notification": silent}
    if keyboard:
        p["reply_markup"] = {"inline_keyboard": keyboard}
    return tg("sendPhoto", p).get("result", {}).get("message_id")

def search(chat, which, term):
    a = ARR[which]
    if which == "m":
        results = arr_get(a, "/movie/lookup?term=" + urllib.parse.quote(term))
    else:
        results = arr_get(a, "/series/lookup?term=" + urllib.parse.quote(term))
    if not results:
        card(chat, WARN + " No " + a["kind"] + " found for <b>" + esc(term) + "</b>.",
             kb(mb_menu_rows()))
        return
    ids = CARDS.setdefault(str(chat), [])
    shown = 0
    for r in results:
        if shown >= 3:
            break
        shown += 1
        year = str(r.get("year", "?"))
        title = r.get("title", "?")
        already = r.get("id", 0) > 0 or r.get("path")
        overview = (r.get("overview") or "")[:180]
        caption = a["icon"] + " " + title + " (" + year + ")\n" + overview
        ext_id = r.get("tmdbId") if which == "m" else r.get("tvdbId")
        if already:
            caption += "\n\n✓ Already in the library"
            keyboard = None
        elif which == "m":
            # note: nested lists are written [ [ … ] ] with a space, because
            # adjacent double open-brackets are nomad-pack template delimiters
            keyboard = [ [{"text": "➕ Add to Radarr", "callback_data": "add:m:" + str(ext_id)}] ]
        else:
            keyboard = [ [{"text": "➕ All seasons", "callback_data": "adds:" + str(ext_id) + ":all"}],
                         [{"text": "➕ Latest season only", "callback_data": "adds:" + str(ext_id) + ":latestSeason"}],
                         [{"text": "➕ Future episodes only", "callback_data": "adds:" + str(ext_id) + ":future"}] ]
        poster = r.get("remotePoster")
        mid = None
        try:
            if poster:
                mid = photo_card(chat, poster, caption, keyboard)
            else:
                raise ValueError("no poster")
        except Exception:
            mid = say(chat, caption, keyboard, silent=True)
        if mid:
            ids.append(mid)

def add(chat, which, ext_id, monitor=None, who=""):
    a = ARR[which]
    if which == "m":
        obj = arr_get(a, "/movie/lookup/tmdb?tmdbId=" + ext_id)
        obj = obj[0] if isinstance(obj, list) else obj
    else:
        obj = arr_get(a, "/series/lookup?term=" + urllib.parse.quote("tvdb:" + ext_id))[0]
    profile = arr_get(a, "/qualityprofile")[0]["id"]
    root = arr_get(a, "/rootfolder")[0]["path"]
    obj.update({"qualityProfileId": profile, "rootFolderPath": root, "monitored": True})
    if which == "m":
        obj["addOptions"] = {"searchForMovie": True}
        added = arr_post(a, "/movie", obj)
        detail = ""
    else:
        obj["addOptions"] = {"monitor": monitor or "all", "searchForMissingEpisodes": True}
        added = arr_post(a, "/series", obj)
        detail = {"all": " (all seasons)", "latestSeason": " (latest season)",
                  "future": " (future episodes)"}.get(monitor or "all", "")
    title = added.get("title", "?") + " (" + str(added.get("year", "?")) + ")"
    forget_cards(chat)          # the choice is made; clear the browsing clutter
    card(chat, OK + " " + a["icon"] + " <b>" + esc(title) + "</b>" + esc(detail)
               + "\n<i>Searching for releases now.</i>",
         kb(mb_menu_rows()))
    for c in ALLOWED - {chat}:
        card(c, a["icon"] + " " + esc(who or "Someone") + " added <b>"
                + esc(title) + "</b>" + esc(detail), kb(mb_menu_rows()))

def mb_view_queue():
    """Progress as a meter, so "nearly done" and "just started" are one glance
    apart. Sorted by progress: the ones about to land are the ones you care
    about."""
    rows = []
    for which in ("m", "s"):
        a = ARR[which]
        try:
            for rec in arr_get(a, "/queue?pageSize=10").get("records", []):
                left = rec.get("sizeleft", 0)
                size = rec.get("size", 1) or 1
                pct = 100.0 * (1 - left / size)
                rows.append((pct, a["icon"], rec.get("title", "?"), left, rec))
        except Exception as e:
            rows.append((-1.0, a["icon"], "queue unavailable: " + str(e)[:50], 0, None))

    lines = ["\U0001f4e5 <b>Download queue</b>", ""]
    if not rows:
        lines.append("<i>empty — all quiet</i>")
        return "\n".join(lines), kb(mb_menu_rows())

    rows.sort(key=lambda r: -r[0])
    for pct, icon, title, left, rec in rows:
        if pct < 0:
            lines.append(WARN + " " + icon + " " + esc(title))
            continue
        # Release names are long and noisy; the title is the first thing you
        # read, so give it the width and drop the scene tags off the end.
        lines.append(icon + " <b>" + esc(clean_release(title)) + "</b>")
        eta = rec.get("timeleft") if rec else None
        tail = "  <i>" + esc(eta) + "</i>" if eta else ""
        lines.append("<code>" + bar(pct) + " " + str(int(pct)).rjust(3) + "%</code>" + tail)
    return "\n".join(lines), kb(mb_menu_rows())


def clean_release(title):
    """Trim a scene release name down to something readable on a phone."""
    t = re.split(r"\b(?:1080p|720p|2160p|480p|BluRay|WEB-?DL|WEBRip|HDTV|REPACK)\b",
                 title, 1)[0]
    t = re.sub(r"^\[" r"[^\]]*\]\s*", "", t).replace(".", " ").strip(" -_")
    return (t or title)[:48]


def mb_view_upcoming():
    out = []
    today = time.strftime("%Y-%m-%d")
    end = time.strftime("%Y-%m-%d", time.localtime(time.time() + 7 * 86400))
    for which in ("m", "s"):
        a = ARR[which]
        try:
            for rec in arr_get(a, "/calendar?start=" + today + "&end=" + end)[:10]:
                t = rec.get("title", "?")
                if which == "s":
                    t += " S" + str(rec.get("seasonNumber", 0)).zfill(2) + \
                         "E" + str(rec.get("episodeNumber", 0)).zfill(2)
                when = str(rec.get("airDate") or rec.get("inCinemas", ""))[:10]
                out.append((when, a["icon"], t))
        except Exception as e:
            out.append(("", a["icon"], "calendar unavailable: " + str(e)[:50]))

    lines = ["\U0001f4c5 <b>Next 7 days</b>", ""]
    if not out:
        lines.append("<i>nothing scheduled</i>")
        return "\n".join(lines), kb(mb_menu_rows())

    out.sort(key=lambda r: r[0])
    last = None
    for when, icon, title in out:
        if when != last:                      # one date header, not a date per row
            lines.append("")
            lines.append("<b>" + esc(day_label(when)) + "</b>")
            last = when
        lines.append("  " + icon + " " + esc(title[:52]))
    return "\n".join(lines), kb(mb_menu_rows())


def day_label(d):
    """Today/Tomorrow read faster than a date you have to decode."""
    if not d:
        return "unscheduled"
    try:
        t = time.mktime(time.strptime(d, "%Y-%m-%d"))
    except Exception:
        return d
    days = int((t - time.mktime(time.strptime(time.strftime("%Y-%m-%d"),
                                              "%Y-%m-%d"))) // 86400)
    return {0: "Today", 1: "Tomorrow"}.get(days, time.strftime("%a %d %b",
                                                               time.localtime(t)))


def slug_to_term(slug):
    # trakt/letterboxd slugs: "dune-part-two-2024" -> "dune part two 2024"
    return slug.replace("-", " ").strip()

def resolve_link(chat, text):
    # Returns True if the text contained a recognizable media link.
    m = re.search(r"\b(tt\d{6,10})\b", text)
    if m:
        imdb = m.group(1)
        try:
            if arr_get(ARR["m"], "/movie/lookup?term=imdb:" + imdb):
                search(chat, "m", "imdb:" + imdb)
                return True
        except Exception:
            pass
        try:
            if arr_get(ARR["s"], "/series/lookup?term=imdb:" + imdb):
                search(chat, "s", "imdb:" + imdb)
                return True
        except Exception:
            pass
        card(chat, WARN + " Found IMDb id " + esc(imdb) + " but neither Radarr nor Sonarr "
                 + "recognize it — is it a short/episode link?",
             kb(mb_menu_rows()))
        return True
    m = re.search(r"themoviedb\.org/(movie|tv)/(\d+)(?:-([\w-]+))?", text)
    if m:
        kind, tmdb_id, slug = m.groups()
        if kind == "movie":
            search(chat, "m", "tmdb:" + tmdb_id)
        else:
            search(chat, "s", slug_to_term(slug) if slug else "tmdb:" + tmdb_id)
        return True
    m = re.search(r"trakt\.tv/(movies|shows)/([\w-]+)", text)
    if m:
        kind, slug = m.groups()
        search(chat, "m" if kind == "movies" else "s", slug_to_term(slug))
        return True
    m = re.search(r"letterboxd\.com/film/([\w-]+)", text)
    if m:
        search(chat, "m", slug_to_term(m.group(1)))
        return True
    return False


def mb_menu_rows():
    row1 = [ {"text": "\U0001f4e5 Queue",    "callback_data": "mb:queue"},
             {"text": "\U0001f4c5 Upcoming", "callback_data": "mb:upcoming"} ]
    row2 = [ {"text": "\U0001f4be Disk",     "callback_data": "mb:disk"},
             {"text": "\U0001f3e0 Home",     "callback_data": "mb:menu"} ]
    return [ row1, row2 ]


def mb_view_disk():
    """Free space as a used-meter, so a filling seedbox is obvious at a glance
    rather than being two numbers to subtract in your head."""
    lines = [ "\U0001f4be <b>Seedbox storage</b>", "" ]
    seen = set()
    for which in ("m", "s"):
        a = ARR[which]
        try:
            for d in arr_get(a, "/diskspace"):
                path = d.get("path", "?")
                if path in seen:
                    continue
                seen.add(path)
                free = d.get("freeSpace", 0)
                total = d.get("totalSpace", 1) or 1
                used_pct = 100.0 * (1 - free / total)
                lines.append("<code>" + esc(path[:14]).ljust(14) + " " + bar(used_pct) +
                             " " + str(int(used_pct)).rjust(3) + "%</code> " + dot(used_pct))
                lines.append("<i>   " + human(free) + " free of " + human(total) + "</i>")
        except Exception as e:
            lines.append(WARN + " " + a["icon"] + " " + esc(str(e)[:50]))
    return "\n".join(lines), kb(mb_menu_rows())


def handle_message(msg):
    chat = str(msg["chat"]["id"])
    if chat not in ALLOWED:
        say(chat, "Not authorized. (Your chat id is " + chat + ")")
        return
    text = msg.get("text", "").strip()
    if not text:
        return
    try:
        if text.startswith("/movie "):
            search(chat, "m", text[7:].strip())
        elif text.startswith("/series ") or text.startswith("/show "):
            search(chat, "s", text.split(" ", 1)[1].strip())
        elif text.startswith("/menu"):
            card(chat, "\U0001f3ac <b>Artback Video Club</b>\n\n"
                       "Send a title, or paste an IMDb / TMDb link.",
                 kb(mb_menu_rows()))
        elif text.startswith("/queue"):
            t, k = mb_view_queue()
            card(chat, t, k)
        elif text.startswith("/disk"):
            t, k = mb_view_disk()
            card(chat, t, k)
        elif text.startswith("/upcoming"):
            t, k = mb_view_upcoming()
            card(chat, t, k)
        elif text.startswith("/"):
            card(chat, "\U0001f3ac <b>Artback Video Club</b>\n\n"
                       "<b>/movie</b> TITLE — search &amp; add to Radarr\n"
                       "<b>/series</b> TITLE — search &amp; add to Sonarr\n"
                       "<b>/queue</b> — current downloads\n"
                       "<b>/upcoming</b> — next 7 days\n"
                       "<b>/disk</b> — seedbox storage\n\n"
                       "<i>Or just send a title, or paste an IMDb / TMDb / "
                       "Trakt / Letterboxd link and I'll decode it.</i>",
                 kb(mb_menu_rows()))
        elif resolve_link(chat, text):
            pass
        else:
            # bare title: search both, movies first
            search(chat, "m", text)
            search(chat, "s", text)
    except Exception as e:
        card(chat, BAD + " That didn't work\n<code>" + esc(str(e)[:180]) + "</code>",
             kb(mb_menu_rows()))

def handle_callback(cb):
    chat = str(cb["message"]["chat"]["id"])
    try:
        tg("answerCallbackQuery", {"callback_query_id": cb["id"]})
    except Exception:
        pass
    if chat not in ALLOWED:
        return
    data = cb.get("data", "")
    if data.startswith("mb:"):
        mid = cb["message"]["message_id"]
        try:
            if data == "mb:disk":
                t, k = mb_view_disk()
                card(chat, t, k, mid)
            elif data == "mb:queue":
                t, k = mb_view_queue()
                card(chat, t, k, mid)
            elif data == "mb:upcoming":
                t, k = mb_view_upcoming()
                card(chat, t, k, mid)
            elif data == "mb:menu":
                card(chat, "\U0001f3ac <b>Artback Video Club</b>\n\n"
           "Send a title, or paste an IMDb / TMDb link.",
                     kb(mb_menu_rows()), mid)
        except Exception as e:
            card(chat, WARN + " " + esc(str(e)[:150]), kb(mb_menu_rows()), mid)
        return
    who = (cb.get("from") or {}).get("first_name", "")
    try:
        if data.startswith("add:"):
            _, which, ext_id = data.split(":")
            add(chat, which, ext_id, who=who)
        elif data.startswith("adds:"):
            _, ext_id, monitor = data.split(":")
            add(chat, "s", ext_id, monitor=monitor, who=who)
    except Exception as e:
        card(chat, BAD + " Add failed\n<code>" + esc(str(e)[:180]) + "</code>",
             kb(mb_menu_rows()))

def main():
    offset = 0
    while True:
        try:
            updates = tg("getUpdates", {"offset": offset, "timeout": 50})
            for u in updates.get("result", []):
                offset = u["update_id"] + 1
                if "message" in u:
                    handle_message(u["message"])
                elif "callback_query" in u:
                    handle_callback(u["callback_query"])
        except Exception as e:
            print("poll error:", e, flush=True)
            time.sleep(5)

main()
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 256
      }
    }
  }
}
