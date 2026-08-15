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

def say(chat, text, keyboard=None):
    p = {"chat_id": chat, "text": text}
    if keyboard:
        p["reply_markup"] = {"inline_keyboard": keyboard}
    try:
        tg("sendMessage", p)
    except Exception as e:
        print("say error:", e, flush=True)

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

def photo_card(chat, photo, caption, keyboard):
    p = {"chat_id": chat, "photo": photo, "caption": caption}
    if keyboard:
        p["reply_markup"] = {"inline_keyboard": keyboard}
    tg("sendPhoto", p)

def search(chat, which, term):
    a = ARR[which]
    if which == "m":
        results = arr_get(a, "/movie/lookup?term=" + urllib.parse.quote(term))
    else:
        results = arr_get(a, "/series/lookup?term=" + urllib.parse.quote(term))
    if not results:
        say(chat, "No " + a["kind"] + " found for '" + term + "'.")
        return
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
        try:
            if poster:
                photo_card(chat, poster, caption, keyboard)
            else:
                raise ValueError("no poster")
        except Exception:
            say(chat, caption, keyboard)

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
    say(chat, a["icon"] + " Added: " + title + detail
             + " — searching for releases now.")
    for c in ALLOWED - {chat}:
        say(c, a["icon"] + " " + (who or "Someone") + " added " + title + detail)

def queue_report(chat):
    out = []
    for which in ("m", "s"):
        a = ARR[which]
        try:
            q = arr_get(a, "/queue?pageSize=10")
            for rec in q.get("records", []):
                title = rec.get("title", "?")[:60]
                left = rec.get("sizeleft", 0)
                size = rec.get("size", 1) or 1
                pct = int(100 * (1 - left / size))
                out.append(a["icon"] + " " + title + " — " + str(pct) + "%")
        except Exception as e:
            out.append(a["icon"] + " queue unavailable: " + str(e))
    say(chat, "⬇️ Download queue:\n" + ("\n".join(out) if out else "empty — all quiet"))

def upcoming(chat):
    out = []
    today = time.strftime("%Y-%m-%d")
    end = time.strftime("%Y-%m-%d", time.localtime(time.time() + 7 * 86400))
    for which in ("m", "s"):
        a = ARR[which]
        try:
            cal = arr_get(a, "/calendar?start=" + today + "&end=" + end)
            for rec in cal[:10]:
                t = rec.get("title", "?")
                if which == "s":
                    t += " S" + str(rec.get("seasonNumber", 0)).zfill(2) + "E" + str(rec.get("episodeNumber", 0)).zfill(2)
                out.append(a["icon"] + " " + t + " — " + str(rec.get("airDate") or rec.get("inCinemas", ""))[:10])
        except Exception as e:
            out.append(a["icon"] + " calendar unavailable: " + str(e))
    say(chat, "🗓 Next 7 days:\n" + ("\n".join(out) if out else "nothing scheduled"))

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
        say(chat, "Found IMDb id " + imdb + " but neither Radarr nor Sonarr "
                 + "recognize it — is it a short/episode link?")
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
        elif text.startswith("/queue"):
            queue_report(chat)
        elif text.startswith("/disk"):
            out = []
            for which in ("m", "s"):
                a = ARR[which]
                try:
                    for d in arr_get(a, "/diskspace"):
                        free = round(d.get("freeSpace", 0) / 1e9)
                        total = round(d.get("totalSpace", 1) / 1e9)
                        out.append(a["icon"] + " " + d.get("path", "?") + " — "
                                   + str(free) + " / " + str(total) + " GB free")
                except Exception as e:
                    out.append(a["icon"] + " diskspace unavailable: " + str(e))
            say(chat, "💾 Seedbox storage:\n" + "\n".join(dict.fromkeys(out)))
        elif text.startswith("/upcoming"):
            upcoming(chat)
        elif text.startswith("/"):
            say(chat, "🎬 Artback Video Club:\n\n"
                     + "/movie TITLE — search & add to Radarr\n"
                     + "/series TITLE — search & add to Sonarr\n"
                     + "/queue — current downloads\n"
                     + "/upcoming — next 7 days\n"
                     + "/disk — seedbox storage\n\n"
                     + "Or just send a title — or paste an IMDb / TMDb / "
                     + "Trakt / Letterboxd link and I'll decode it.")
        elif resolve_link(chat, text):
            pass
        else:
            # bare title: search both, movies first
            search(chat, "m", text)
            search(chat, "s", text)
    except Exception as e:
        say(chat, "That didn't work: " + str(e))

def handle_callback(cb):
    chat = str(cb["message"]["chat"]["id"])
    try:
        tg("answerCallbackQuery", {"callback_query_id": cb["id"]})
    except Exception:
        pass
    if chat not in ALLOWED:
        return
    data = cb.get("data", "")
    who = (cb.get("from") or {}).get("first_name", "")
    try:
        if data.startswith("add:"):
            _, which, ext_id = data.split(":")
            add(chat, which, ext_id, who=who)
        elif data.startswith("adds:"):
            _, ext_id, monitor = data.split(":")
            add(chat, "s", ext_id, monitor=monitor, who=who)
    except Exception as e:
        say(chat, "Add failed: " + str(e))

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
