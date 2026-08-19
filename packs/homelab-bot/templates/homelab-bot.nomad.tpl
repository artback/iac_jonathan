job "homelab-bot" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "bot" {
    count = 1

    # Outbound only: long-polls Telegram, reads the Nomad and Prometheus APIs.
    # No ports, no service registration.
    restart {
      attempts = 3
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    task "bot" {
      driver = "docker"

      config {
        image   = "[[ var "image" . ]]"
        command = "python3"
        args    = ["/local/bot.py"]
        volumes = [
          "[[ var "certs_dir" . ]]:/certs:ro",
          "[[ var "backup_dir" . ]]:/backups:ro",
        ]
      }

      env {
        NOMAD_ADDR        = "[[ var "nomad_addr" . ]]"
        NOMAD_CACERT      = "/certs/nomad-ca.pem"
        NOMAD_CLIENT_CERT = "/certs/nomad-client.pem"
        NOMAD_CLIENT_KEY  = "/certs/nomad-client-key.pem"
        PROMETHEUS_URL    = "[[ var "prometheus_url" . ]]"
        BACKUP_DIR        = "/backups"
        ALLOWED_CHAT_IDS  = "[[ var "allowed_chat_ids" . ]]"
      }

      # Telegram token and a READ-ONLY Nomad token, both from Nomad Variables.
      # The Nomad token carries the homelab-bot-readonly policy: it can read
      # jobs and logs and nothing else, so a compromised bot cannot alter the
      # cluster it reports on.
      template {
        destination = "secrets/bot.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{ with nomadVar "nomad/jobs/homelab-bot" }}
TELEGRAM_TOKEN={{ .telegram_token }}
NOMAD_TOKEN={{ index . "nomad_token" }}
{{ end }}
EOH
      }

      template {
        destination = "local/bot.py"
        change_mode = "restart"
        perms       = "755"
        # Python only; consul-template must not try to parse it.
        left_delimiter  = "<<<"
        right_delimiter = ">>>"
        data        = <<EOH
import json, os, ssl, time, urllib.error, urllib.parse, urllib.request

TOKEN   = os.environ["TELEGRAM_TOKEN"]
ALLOWED = set(x.strip() for x in os.environ.get("ALLOWED_CHAT_IDS", "").split(",") if x.strip())
NOMAD   = os.environ["NOMAD_ADDR"].rstrip("/")
PROM    = os.environ["PROMETHEUS_URL"].rstrip("/")
BACKUPS = os.environ.get("BACKUP_DIR", "/backups")

CTX = ssl.create_default_context(cafile=os.environ["NOMAD_CACERT"])
CTX.load_cert_chain(os.environ["NOMAD_CLIENT_CERT"], os.environ["NOMAD_CLIENT_KEY"])

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

def nomad(path):
    import json, urllib.request
    req = urllib.request.Request(NOMAD + path,
                                 headers={"X-Nomad-Token": os.environ["NOMAD_TOKEN"]})
    with urllib.request.urlopen(req, context=CTX, timeout=20) as r:
        return json.load(r)


def prom(query):
    import json, urllib.parse, urllib.request
    url = PROM + "/api/v1/query?query=" + urllib.parse.quote(query)
    with urllib.request.urlopen(url, timeout=20) as r:
        res = json.load(r)["data"]["result"]
    return float(res[0]["value"][1]) if res else None


def nav_row(cur):
    """Refresh has to re-run the view you are on. A single "Refresh" wired to
    the home action just navigates away, which is the opposite of refreshing —
    so each view names itself here."""
    return [ {"text": "\U0001f504 Refresh", "callback_data": cur},
             {"text": "\u2190 Menu",        "callback_data": "menu"} ]


def menu_rows():
    row1 = [ {"text": "\U0001f4ca Status", "callback_data": "status"},
             {"text": "\U0001f4e6 Jobs",   "callback_data": "jobs"} ]
    row2 = [ {"text": "\U0001f5a5 Usage",  "callback_data": "usage"},
             {"text": "\U0001f4be Backup", "callback_data": "backup"} ]
    row3 = [ {"text": "\U0001f4dc Logs",   "callback_data": "logmenu"},
             {"text": "\U0001f504 Refresh","callback_data": "status"} ]
    return [ row1, row2, row3 ]



def job_states():
    jobs = nomad("/v1/jobs")
    live, broken = [], []
    for j in jobs:
        if j["Type"] == "batch" or j.get("Periodic"):
            continue
        (live if j["Status"] == "running" else broken).append(j)
    return jobs, live, broken


def view_status():
    jobs, live, broken = job_states()
    head = OK if not broken else BAD
    lines = [ head + " <b>Homelab</b>", "" ]
    lines.append("<b>Jobs</b>  " + str(len(live)) + " running" +
                 ("" if not broken else ", <b>" + str(len(broken)) + " down</b>"))
    for j in broken[:6]:
        lines.append("   " + BAD + " " + esc(j["ID"]) + " — " + j["Status"])
    try:
        nodes = nomad("/v1/nodes")
        for n in nodes:
            mark = OK if n["Status"] == "ready" else BAD
            lines.append("<b>Node</b>  " + mark + " " + esc(n["Name"]) + " " + n["Status"])
    except Exception:
        lines.append("<b>Node</b>  " + WARN + " unreadable")
    lines.append("")
    lines.append(backup_line())
    try:
        cpu = prom("100 - (avg(rate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)")
        mem = prom("100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)")
        if cpu is not None and mem is not None:
            lines.append("")
            lines.append("<code>cpu " + bar(cpu) + " " + str(int(cpu)).rjust(3) + "%</code>")
            lines.append("<code>mem " + bar(mem) + " " + str(int(mem)).rjust(3) + "%</code>")
    except Exception:
        pass
    return "\n".join(lines), kb(menu_rows())


def view_jobs():
    jobs, live, broken = job_states()
    lines = [ "\U0001f4e6 <b>Jobs</b>", "" ]
    for j in broken:
        lines.append(BAD + " <b>" + esc(j["ID"]) + "</b> — " + j["Status"])
    if broken:
        lines.append("")
    names = sorted((j["ID"] for j in live), key=str.lower)
    lines.append("<code>" + esc("  ".join(names)) + "</code>" if names else "none running")
    rows = []
    for j in broken[:6]:
        rows.append([ {"text": "\U0001f4dc " + j["ID"][:24],
                       "callback_data": "log:" + j["ID"][:40]} ])
    rows.append(back_row())
    return "\n".join(lines), kb(rows)


def view_usage():
    items = [ ("cpu",  "100 - (avg(rate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)", "%"),
              ("mem",  "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)", "%"),
              ("disk", "100 * (1 - node_filesystem_avail_bytes{mountpoint='/'} / node_filesystem_size_bytes{mountpoint='/'})", "%") ]
    lines = [ "\U0001f5a5 <b>System</b>", "" ]
    worst = 0.0
    for label, expr, unit in items:
        try:
            v = prom(expr)
        except Exception:
            v = None
        if v is None:
            lines.append("<code>" + label.ljust(4) + " unavailable</code>")
            continue
        worst = max(worst, v)
        lines.append("<code>" + label.ljust(4) + " " + bar(v) + " " +
                     str(int(v)).rjust(3) + unit + "</code> " + dot(v))
    try:
        load = prom("node_load1")
        upt = prom("node_time_seconds - node_boot_time_seconds")
        if load is not None:
            lines.append("")
            lines.append("load " + str(round(load, 2)))
        if upt is not None:
            lines.append("up   " + ago(upt).replace(" ago", ""))
    except Exception:
        pass
    return "\n".join(lines), kb([ nav_row("usage") ])


def backup_line():
    try:
        files = [ os.path.join(BACKUPS, f) for f in os.listdir(BACKUPS) if f.endswith(".gz") ]
        if not files:
            return BAD + " <b>Backup</b>  none found"
        newest = max(files, key=os.path.getmtime)
        age = time.time() - os.path.getmtime(newest)
        mark = OK if age < 30 * 3600 else BAD
        return (mark + " <b>Backup</b>  " + ago(age) + ", " +
                human(os.path.getsize(newest)))
    except Exception as e:
        return WARN + " <b>Backup</b>  " + esc(str(e)[:40])


def view_backup():
    lines = [ "\U0001f4be <b>Backups</b>", "" ]
    try:
        files = [ os.path.join(BACKUPS, f) for f in os.listdir(BACKUPS) if f.endswith(".gz") ]
        for p in sorted(files, key=os.path.getmtime, reverse=True)[:7]:
            age = time.time() - os.path.getmtime(p)
            lines.append("<code>" + ago(age).rjust(7) + "  " +
                         human(os.path.getsize(p)).rjust(7) + "</code>  " +
                         esc(os.path.basename(p))[:28])
        if not files:
            lines.append(BAD + " nothing in " + esc(BACKUPS))
    except Exception as e:
        lines.append(WARN + " " + esc(str(e)[:60]))
    return "\n".join(lines), kb([ nav_row("backup") ])


def view_logmenu():
    jobs, live, broken = job_states()
    names = sorted((j["ID"] for j in live + broken), key=str.lower)
    rows, row = [], []
    for n in names:
        row.append({"text": n[:18], "callback_data": "log:" + n[:40]})
        if len(row) == 2:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    rows.append(back_row())
    return "\U0001f4dc <b>Logs</b>\n\nPick a job.", kb(rows)


def view_logs(job):
    try:
        allocs = nomad("/v1/job/" + urllib.parse.quote(job) + "/allocations")
    except Exception as e:
        return WARN + " " + esc(str(e)[:80]), kb([ back_row() ])
    live = [ a for a in allocs if a["ClientStatus"] == "running" ] or allocs
    if not live:
        return WARN + " no allocations for " + esc(job), kb([ back_row() ])
    a = sorted(live, key=lambda x: x["ModifyIndex"])[-1]
    task = list(a["TaskStates"].keys())[0]
    text = ""
    for stream in ("stderr", "stdout"):
        url = ("/v1/client/fs/logs/" + a["ID"] + "?task=" + urllib.parse.quote(task) +
               "&type=" + stream + "&origin=end&offset=4000&plain=true")
        try:
            req = urllib.request.Request(NOMAD + url,
                                         headers={"X-Nomad-Token": os.environ["NOMAD_TOKEN"]})
            with urllib.request.urlopen(req, context=CTX, timeout=25) as r:
                text = r.read().decode("utf-8", "replace")
        except Exception:
            text = ""
        if text.strip():
            break
    tail = "\n".join(text.splitlines()[-18:]) or "(no output)"
    rows = [ nav_row("log:" + job[:40]) ]
    return ("\U0001f4dc <b>" + esc(job) + "</b> — " + esc(task) + "\n\n<pre>" +
            esc(tail[-3200:]) + "</pre>"), kb(rows)


def render(action):
    if action == "status" or action == "menu":
        return view_status()
    if action == "jobs":
        return view_jobs()
    if action == "usage":
        return view_usage()
    if action == "backup":
        return view_backup()
    if action == "logmenu":
        return view_logmenu()
    if action.startswith("log:"):
        return view_logs(action[4:])
    return view_status()


def main():
    offset = 0
    print("homelab-bot up", flush=True)
    while True:
        try:
            url = ("https://api.telegram.org/bot" + TOKEN +
                   "/getUpdates?timeout=50&allowed_updates=" +
                   urllib.parse.quote(json.dumps([ "message", "callback_query" ])) +
                   "&offset=" + str(offset))
            with urllib.request.urlopen(url, timeout=70) as r:
                updates = json.load(r).get("result", [])
            for u in updates:
                offset = u["update_id"] + 1
                cq = u.get("callback_query")
                if cq:
                    chat = str(cq["message"]["chat"]["id"])
                    if ALLOWED and chat not in ALLOWED:
                        continue
                    tg("answerCallbackQuery", {"callback_query_id": cq["id"]})
                    try:
                        text, markup = render(cq.get("data", "status"))
                    except Exception as e:
                        text, markup = WARN + " " + esc(str(e)[:200]), kb([ back_row() ])
                    # Editing in place keeps one tidy card instead of a wall of
                    # replies, which is the whole point on a phone.
                    card(chat, text, markup, cq["message"]["message_id"])
                    continue
                msg = u.get("message") or {}
                body = (msg.get("text") or "").strip()
                chat = str((msg.get("chat") or {}).get("id", ""))
                if not body.startswith("/") or (ALLOWED and chat not in ALLOWED):
                    continue
                cmd = body.split()[0].lower().split("@")[0].lstrip("/")
                arg = body.split(None, 1)[1].strip() if len(body.split(None, 1)) > 1 else ""
                action = {"start": "menu", "menu": "menu", "status": "status",
                          "jobs": "jobs", "usage": "usage", "backup": "backup",
                          "logs": ("log:" + arg) if arg else "logmenu"}.get(cmd)
                if not action:
                    action = "menu"      # silence reads as a broken bot
                try:
                    text, markup = render(action)
                except Exception as e:
                    text, markup = WARN + " " + esc(str(e)[:200]), kb([ back_row() ])
                card(chat, text, markup)
        except Exception as e:
            print("loop error: " + str(e)[:200], flush=True)
            time.sleep(5)


main()
EOH
      }

      resources {
        cpu    = [[ var "cpu" . ]]
        memory = [[ var "memory" . ]]
      }
    }
  }
}
