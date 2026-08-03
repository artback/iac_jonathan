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
          TELEGRAM_TOKEN="[[ var "telegram_token" . ]]"
          ALLOWED_CHAT_IDS="[[ var "allowed_chat_ids" . ]]"
          RADARR_URL="[[ var "radarr_url" . ]]"
          RADARR_KEY="[[ var "radarr_api_key" . ]]"
          SONARR_URL="[[ var "sonarr_url" . ]]"
          SONARR_KEY="[[ var "sonarr_api_key" . ]]"
        EOH
      }

      # Outbound long-polling only — nothing exposed. Search results use
      # inline keyboards; adds run with the instance's first quality
      # profile and root folder, and trigger an immediate release search.
      template {
        destination = "local/bot.py"
        change_mode = "restart"
        data        = <<EOH
import json, os, time, urllib.request, urllib.parse

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

def search(chat, which, term):
    a = ARR[which]
    if which == "m":
        results = arr_get(a, "/movie/lookup?term=" + urllib.parse.quote(term))
    else:
        results = arr_get(a, "/series/lookup?term=" + urllib.parse.quote(term))
    if not results:
        say(chat, "No " + a["kind"] + " found for '" + term + "'.")
        return
    lines, buttons = [], []
    for i, r in enumerate(results[:5]):
        year = str(r.get("year", "?"))
        title = r.get("title", "?")
        already = r.get("id", 0) > 0 or r.get("path")
        mark = " — already added ✓" if already else ""
        lines.append(str(i + 1) + ". " + title + " (" + year + ")" + mark)
        if not already:
            ext_id = r.get("tmdbId") if which == "m" else r.get("tvdbId")
            buttons.append([{"text": "➕ " + str(i + 1) + ". " + title[:40] + " (" + year + ")",
                             "callback_data": "add:" + which + ":" + str(ext_id)}])
    say(chat, a["icon"] + " Results for '" + term + "':\n\n" + "\n".join(lines)
             + ("\n\nTap to add:" if buttons else "\n\nEverything is already in the library."),
        buttons or None)

def add(chat, which, ext_id):
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
    else:
        obj["addOptions"] = {"searchForMissingEpisodes": True}
        added = arr_post(a, "/series", obj)
    say(chat, a["icon"] + " Added: " + added.get("title", "?")
             + " (" + str(added.get("year", "?")) + ") — searching for releases now. "
             + "You'll get the usual download updates.")

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
        elif text.startswith("/upcoming"):
            upcoming(chat)
        elif text.startswith("/"):
            say(chat, "🎬 Artback Video Club:\n\n"
                     + "/movie TITLE — search & add to Radarr\n"
                     + "/series TITLE — search & add to Sonarr\n"
                     + "/queue — current downloads\n"
                     + "/upcoming — next 7 days\n\n"
                     + "Or just send a title and I'll search movies + series.")
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
    if data.startswith("add:"):
        _, which, ext_id = data.split(":")
        try:
            add(chat, which, ext_id)
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
