job "printbot" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "printbot-group" {
    count = 1

    task "bot" {
      driver = "docker"

      config {
        image   = "python:3.12-alpine"
        command = "sh"
        args    = ["-c", "apk add --no-cache cups-client >/dev/null 2>&1 && exec python /local/bot.py"]
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
          CUPS_SERVER="[[ var "cups_server" . ]]"
          PRINTER="[[ var "printer" . ]]"
        EOH
      }

      # Outbound long-polling only: no ports, no webhook, nothing exposed.
      template {
        destination = "local/bot.py"
        change_mode = "restart"
        data        = <<EOH
import json, os, subprocess, tempfile, time, urllib.request, urllib.parse

TOKEN = os.environ["TELEGRAM_TOKEN"]
API = "https://api.telegram.org/bot" + TOKEN
ALLOWED = {s.strip() for s in os.environ.get("ALLOWED_CHAT_IDS", "").split(",") if s.strip()}
CUPS = os.environ["CUPS_SERVER"]
PRINTER = os.environ["PRINTER"]
OK_MIME = ("application/pdf", "image/jpeg", "image/png", "text/plain")

def api(method, **params):
    data = urllib.parse.urlencode(params).encode()
    with urllib.request.urlopen(API + "/" + method, data, timeout=70) as r:
        return json.load(r)

def say(chat, text):
    try:
        api("sendMessage", chat_id=chat, text=text)
    except Exception:
        pass

def queue_status():
    r = subprocess.run(["lpstat", "-h", CUPS, "-p", PRINTER, "-o"],
                       capture_output=True, text=True, timeout=15)
    return (r.stdout + r.stderr).strip() or "queue empty, printer idle"

def print_file(path, title):
    r = subprocess.run(["lp", "-h", CUPS, "-d", PRINTER, "-t", title, path],
                       capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.strip()

def handle(msg):
    chat = str(msg["chat"]["id"])
    if chat not in ALLOWED:
        say(chat, "Not authorized. Your chat id is " + chat)
        return
    text = msg.get("text", "")
    if text.startswith("/status"):
        say(chat, queue_status())
        return
    if text.startswith("/start") or (text and not msg.get("document") and not msg.get("photo")):
        say(chat, "Send me a PDF, JPEG, PNG or .txt and I will print it on " + PRINTER
                 + ". If the printer is off, the job waits in the queue. /status shows the queue.")
        return
    doc = msg.get("document")
    if doc and doc.get("mime_type") not in OK_MIME:
        say(chat, "Only PDF, JPEG, PNG or plain text - got " + str(doc.get("mime_type")))
        return
    if msg.get("photo"):
        doc = max(msg["photo"], key=lambda p: p.get("file_size", 0))
        doc["file_name"] = "photo.jpg"
    if not doc:
        return
    info = api("getFile", file_id=doc["file_id"])
    url = "https://api.telegram.org/file/bot" + TOKEN + "/" + info["result"]["file_path"]
    name = doc.get("file_name", "telegram-print")
    with tempfile.NamedTemporaryFile(suffix="-" + name, delete=False) as f:
        with urllib.request.urlopen(url, timeout=120) as r:
            f.write(r.read())
        tmp = f.name
    try:
        job = print_file(tmp, name)
        say(chat, "Queued: " + job + "\n(prints when the printer is on)")
    except Exception as e:
        say(chat, "Print failed: " + str(e))
    finally:
        os.unlink(tmp)

def main():
    offset = 0
    while True:
        try:
            updates = api("getUpdates", offset=offset, timeout=50)
            for u in updates.get("result", []):
                offset = u["update_id"] + 1
                if "message" in u:
                    handle(u["message"])
        except Exception as e:
            print("poll error:", e, flush=True)
            time.sleep(5)

main()
EOH
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
