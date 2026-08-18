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

# Nomad speaks mTLS here (verify_https_client = true), so a plain urlopen is
# refused at the handshake regardless of the ACL token.
CTX = ssl.create_default_context(cafile=os.environ["NOMAD_CACERT"])
CTX.load_cert_chain(os.environ["NOMAD_CLIENT_CERT"], os.environ["NOMAD_CLIENT_KEY"])

def nomad(path):
    req = urllib.request.Request(NOMAD + path,
                                 headers={"X-Nomad-Token": os.environ["NOMAD_TOKEN"]})
    with urllib.request.urlopen(req, context=CTX, timeout=20) as r:
        return json.load(r)

def prom(query):
    url = PROM + "/api/v1/query?query=" + urllib.parse.quote(query)
    with urllib.request.urlopen(url, timeout=20) as r:
        res = json.load(r)["data"]["result"]
    return float(res[0]["value"][1]) if res else None

def say(chat, text):
    body = urllib.parse.urlencode({"chat_id": chat, "text": text[:4000],
                                   "disable_web_page_preview": "true"}).encode()
    urllib.request.urlopen(
        "https://api.telegram.org/bot" + TOKEN + "/sendMessage", data=body, timeout=30).read()

def human(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024:
            return str(round(n, 1)) + unit
        n /= 1024
    return str(round(n, 1)) + "PB"

def cmd_status():
    out = []
    jobs = nomad("/v1/jobs")
    bad = [j for j in jobs if j["Status"] != "running" and j["Type"] != "batch"]
    out.append("Jobs: " + str(len(jobs)) + " total, " + str(len(bad)) + " not running")
    for j in bad[:8]:
        out.append("  - " + j["ID"] + ": " + j["Status"])
    try:
        nodes = nomad("/v1/nodes")
        out.append("Nodes: " + ", ".join(n["Name"] + "=" + n["Status"] for n in nodes))
    except Exception as e:
        out.append("Nodes: unreadable (" + str(e)[:40] + ")")
    out.append(cmd_backup())
    return "\n".join(out)

def cmd_jobs():
    rows = []
    for j in sorted(nomad("/v1/jobs"), key=lambda x: x["ID"].lower()):
        mark = "ok" if j["Status"] == "running" else j["Status"].upper()
        rows.append(mark.ljust(8) + j["ID"])
    return "\n".join(rows) or "no jobs"

def cmd_usage():
    q = {
        "cpu %":  "100 - (avg(rate(node_cpu_seconds_total{mode='idle'}[5m])) * 100)",
        "mem %":  "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)",
        "disk /": "100 * (1 - node_filesystem_avail_bytes{mountpoint='/'} / node_filesystem_size_bytes{mountpoint='/'})",
        "load1":  "node_load1",
    }
    out = []
    for label, expr in q.items():
        try:
            v = prom(expr)
            out.append(label.ljust(8) + ("n/a" if v is None else str(round(v, 1))))
        except Exception as e:
            out.append(label.ljust(8) + "error " + str(e)[:30])
    return "\n".join(out)

def cmd_backup():
    try:
        files = [os.path.join(BACKUPS, f) for f in os.listdir(BACKUPS) if f.endswith(".gz")]
        if not files:
            return "Backup: NONE FOUND"
        newest = max(files, key=os.path.getmtime)
        age_h = (time.time() - os.path.getmtime(newest)) / 3600
        return ("Backup: " + os.path.basename(newest) + ", " + str(round(age_h, 1)) +
                "h old, " + human(os.path.getsize(newest)))
    except Exception as e:
        return "Backup: error " + str(e)[:50]

def cmd_logs(arg):
    if not arg:
        return "usage: /logs <job>"
    allocs = nomad("/v1/job/" + urllib.parse.quote(arg) + "/allocations")
    live = [a for a in allocs if a["ClientStatus"] == "running"] or allocs
    if not live:
        return "no allocations for " + arg
    a = sorted(live, key=lambda x: x["ModifyIndex"])[-1]
    task = list(a["TaskStates"].keys())[0]
    url = ("/v1/client/fs/logs/" + a["ID"] + "?task=" + urllib.parse.quote(task) +
           "&type=stderr&origin=end&offset=6000&plain=true")
    try:
        req = urllib.request.Request(NOMAD + url,
                                     headers={"X-Nomad-Token": os.environ["NOMAD_TOKEN"]})
        with urllib.request.urlopen(req, context=CTX, timeout=25) as r:
            text = r.read().decode("utf-8", "replace")
    except Exception as e:
        return "log fetch failed: " + str(e)[:80]
    tail = "\n".join(text.splitlines()[-25:])
    return (arg + " / " + task + " (stderr)\n\n" + tail) if tail.strip() else "no stderr output"

HELP = ("/status  cluster summary\n"
        "/jobs    every job and its state\n"
        "/usage   cpu, memory, disk, load\n"
        "/backup  newest database dump\n"
        "/logs J  last stderr lines for job J")

def handle(text):
    parts = text.strip().split(None, 1)
    c = parts[0].lower().split("@")[0]
    arg = parts[1].strip() if len(parts) > 1 else ""
    if c == "/status":  return cmd_status()
    if c == "/jobs":    return cmd_jobs()
    if c == "/usage":   return cmd_usage()
    if c == "/backup":  return cmd_backup()
    if c == "/logs":    return cmd_logs(arg)
    if c in ("/help", "/start"): return HELP
    return None

def main():
    offset = 0
    print("homelab-bot up", flush=True)
    while True:
        try:
            url = ("https://api.telegram.org/bot" + TOKEN +
                   "/getUpdates?timeout=50&offset=" + str(offset))
            with urllib.request.urlopen(url, timeout=70) as r:
                updates = json.load(r).get("result", [])
            for u in updates:
                offset = u["update_id"] + 1
                msg = u.get("message") or {}
                text = msg.get("text") or ""
                chat = str((msg.get("chat") or {}).get("id", ""))
                if not text.startswith("/"):
                    continue
                if ALLOWED and chat not in ALLOWED:
                    print("ignored chat " + chat, flush=True)
                    continue
                try:
                    reply = handle(text)
                except Exception as e:
                    reply = "error: " + str(e)[:200]
                if reply:
                    say(chat, reply)
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
