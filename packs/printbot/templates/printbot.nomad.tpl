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
          GOTENBERG="[[ var "gotenberg_url" . ]]"
        EOH
      }

      # Outbound long-polling only: no ports, no webhook, nothing exposed.
      template {
        destination = "local/bot.py"
        change_mode = "restart"
        data        = <<EOH
import json, os, re, subprocess, tempfile, threading, time, urllib.request, urllib.parse

TOKEN = os.environ["TELEGRAM_TOKEN"]
API = "https://api.telegram.org/bot" + TOKEN
ALLOWED = {s.strip() for s in os.environ.get("ALLOWED_CHAT_IDS", "").split(",") if s.strip()}
CUPS = os.environ["CUPS_SERVER"]
PRINTER = os.environ["PRINTER"]
GOTENBERG = os.environ.get("GOTENBERG", "")
OK_MIME = ("application/pdf", "image/jpeg", "image/png", "text/plain")
CONVERT_EXT = (".docx", ".doc", ".odt", ".xlsx", ".xls", ".ods",
               ".pptx", ".ppt", ".odp", ".rtf")

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

def to_pdf(path, name):
    # multipart POST to gotenberg /forms/libreoffice/convert, stdlib only
    boundary = "----printbot" + str(int(time.time()))
    with open(path, "rb") as f:
        content = f.read()
    body = (("--" + boundary + "\r\n"
             + 'Content-Disposition: form-data; name="files"; filename="' + name + '"\r\n'
             + "Content-Type: application/octet-stream\r\n\r\n").encode()
            + content + ("\r\n--" + boundary + "--\r\n").encode())
    req = urllib.request.Request(
        GOTENBERG + "/forms/libreoffice/convert", data=body,
        headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(req, timeout=180) as r:
        pdf = r.read()
    out = path + ".pdf"
    with open(out, "wb") as f:
        f.write(pdf)
    return out

def print_file(path, title):
    r = subprocess.run(["lp", "-h", CUPS, "-d", PRINTER, "-t", title, path],
                       capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    m = re.search(r"request id is (\S+)", r.stdout)
    return m.group(1) if m else r.stdout.strip()

def watch_job(chat, job, name):
    # The queue is the source of truth: job gone + in completed = printed;
    # gone but not completed = canceled/failed; still queued = printer off.
    nudged = False
    for i in range(400):  # ~12h
        time.sleep(5 if i < 12 else 120)
        pending = subprocess.run(["lpstat", "-h", CUPS, "-o"],
                                 capture_output=True, text=True, timeout=15).stdout
        if job not in pending:
            done = subprocess.run(["lpstat", "-h", CUPS, "-W", "completed", "-o"],
                                  capture_output=True, text=True, timeout=15).stdout
            if job in done:
                say(chat, "Printed: " + name + " ✅")
            else:
                say(chat, "The printer rejected " + name
                         + " ❌ — check /status or try a different format.")
            return
        if not nudged and i >= 11:
            say(chat, "The printer looks offline — " + name + " is safely queued "
                     + "and will print automatically when it's powered on. ⏳")
            nudged = True
    say(chat, "Gave up watching " + name + " after 12h — check /status.")

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
        say(chat, "Send me a PDF, photo, text file or office doc (docx/xlsx/pptx/odt) "
                 + "and I will print it on " + PRINTER
                 + ". If the printer is off, the job waits in the queue. /status shows the queue.")
        return
    doc = msg.get("document")
    convert = False
    if doc:
        name_l = doc.get("file_name", "").lower()
        if doc.get("mime_type") in OK_MIME:
            pass
        elif GOTENBERG and name_l.endswith(CONVERT_EXT):
            convert = True
        else:
            say(chat, "Can't print " + str(doc.get("mime_type"))
                     + ". I take PDF, images, text, or office docs (docx/xlsx/pptx/odt...).")
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
    pdf_tmp = None
    try:
        target = tmp
        if convert:
            say(chat, "Converting " + name + " to PDF…")
            pdf_tmp = to_pdf(tmp, name)
            target = pdf_tmp
        job = print_file(target, name)
        say(chat, "Job " + job.rsplit("-", 1)[-1] + " accepted 🖨️ …")
        threading.Thread(target=watch_job, args=(chat, job, name), daemon=True).start()
    except Exception as e:
        say(chat, "Print failed: " + str(e))
    finally:
        os.unlink(tmp)
        if pdf_tmp:
            os.unlink(pdf_tmp)

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
