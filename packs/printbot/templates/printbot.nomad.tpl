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
        args    = ["-c", "apk add --no-cache cups-client >/dev/null 2>&1; exec python /local/bot.py"]
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
INK_URL = os.environ.get("INK_URL", "http://100.116.81.88/ink.json")
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
    try:
        watch_job_inner(chat, job, name)
    except Exception as e:
        print("watcher error:", e, flush=True)

def watch_job_inner(chat, job, name):
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
                say(chat, "Printed: " + name + " ✅ And it didn't even catch fire.")
            else:
                say(chat, "The printer has rejected " + name + " ❌ Sabre's official "
                         + "position is that this is a feature. Check /status "
                         + "or try a different format.")
            return
        if not nudged and i >= 11:
            say(chat, "The printer appears to be powered off. " + name + " is safely "
                     + "queued and prints the moment it wakes up ⏳ "
                     + "A Sabre product never forgets. Unlike Creed.")
            nudged = True
    say(chat, "After 12 hours, Sabre has decided " + name
             + " is now Dunder Mifflin's problem. Check /status.")

def handle(msg):
    chat = str(msg["chat"]["id"])
    if chat not in ALLOWED:
        say(chat, "You are not an authorized Sabre customer. "
                 + "This incident will be reported to Jo Bennett. "
                 + "(Your chat id is " + chat + ")")
        return
    text = msg.get("text", "")
    if text.startswith("/help"):
        say(chat, "📋 Sabre Command Suite (it's pronounced 'SAH-bray'):\n\n"
                 + "Send any file or photo — prints it\n"
                 + "/status — queue + printer state\n"
                 + "/ink — cartridge levels\n"
                 + "/cancel N — cancel job N\n"
                 + "/clear — cancel every waiting job\n"
                 + "/help — this list")
        return
    if text.startswith("/status"):
        try:
            say(chat, "📋 Sabre Quality Assurance Report:\n" + queue_status())
        except Exception as e:
            say(chat, "Couldn't reach the print queue: " + str(e))
        return
    if text.startswith("/clear"):
        try:
            pending = subprocess.run(["lpstat", "-h", CUPS, "-o"],
                                     capture_output=True, text=True, timeout=15).stdout
            jobs = re.findall(r"^(\S+-\d+)", pending, re.M)
            if not jobs:
                say(chat, "The queue is already empty. Sabre efficiency.")
                return
            failed = []
            for j in jobs:
                r = subprocess.run(["cancel", "-h", CUPS, j],
                                   capture_output=True, text=True, timeout=15)
                if r.returncode != 0:
                    failed.append(j + ": " + r.stderr.strip())
            msg = "Canceled " + str(len(jobs) - len(failed)) + " job(s) 🧹"
            if failed:
                msg += "\nCouldn't cancel:\n" + "\n".join(failed)
            say(chat, msg)
        except Exception as e:
            say(chat, "Clear failed: " + str(e))
        return
    if text.startswith("/cancel"):
        m = re.search(r"/cancel\s+(\d+)", text)
        if not m:
            say(chat, "Usage: /cancel N  (job number from /status)")
            return
        j = PRINTER + "-" + m.group(1)
        r = subprocess.run(["cancel", "-h", CUPS, j],
                           capture_output=True, text=True, timeout=15)
        say(chat, ("Canceled " + j + " 🧹") if r.returncode == 0
                 else "Couldn't cancel " + j + ": " + r.stderr.strip())
        return
    if text.startswith("/ink"):
        try:
            with urllib.request.urlopen(INK_URL, timeout=15) as r:
                d = json.load(r)
            bars = []
            for s in d.get("supplies", []):
                pct = s["percent"]
                bar = "▓" * (pct // 10) + "░" * (10 - pct // 10)
                bars.append(s["name"] + "\n" + bar + " " + str(pct) + "%  (" + s["health"] + ")")
            say(chat, "🖋 Sabre Ink Audit (as of " + d.get("updated", "?") + "):\n\n"
                     + "\n\n".join(bars))
        except Exception as e:
            say(chat, "Ink check failed: " + str(e))
        return
    if text.startswith("/start") or (text and not msg.get("document") and not msg.get("photo")):
        say(chat, "Welcome to Sabre Printing Solutions. It's pronounced 'SAH-bray.'\n\n"
                 + "Send a PDF, photo, text file or office doc (docx/xlsx/pptx/odt) "
                 + "and it prints on " + PRINTER + ". Printer off? The job waits — "
                 + "a Sabre product never forgets.\n\n/help — all commands")
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
            say(chat, "Sabre does not currently support " + str(doc.get("mime_type"))
                     + ". Our engineers in Tallahassee accept PDF, images, text, "
                     + "or office docs (docx/xlsx/pptx/odt...).")
            return
    if msg.get("photo"):
        doc = max(msg["photo"], key=lambda p: p.get("file_size", 0))
        doc["file_name"] = "photo.jpg"
    if not doc:
        return
    name = doc.get("file_name", "telegram-print")
    tmp = None
    pdf_tmp = None
    try:
        # bot API refuses files >20MB — surface that instead of failing silently
        info = api("getFile", file_id=doc["file_id"])
        url = "https://api.telegram.org/file/bot" + TOKEN + "/" + info["result"]["file_path"]
        with tempfile.NamedTemporaryFile(suffix="-" + name, delete=False) as f:
            with urllib.request.urlopen(url, timeout=120) as r:
                f.write(r.read())
            tmp = f.name
        target = tmp
        if convert:
            say(chat, "Routing " + name + " through the Sabre Document Excellence Pipeline™…")
            pdf_tmp = to_pdf(tmp, name)
            target = pdf_tmp
        job = print_file(target, name)
        say(chat, "Sabre job " + job.rsplit("-", 1)[-1] + " accepted 🖨️ It's pronounced 'SAH-bray.'")
        threading.Thread(target=watch_job, args=(chat, job, name), daemon=True).start()
    except Exception as e:
        note = " (Telegram bots can only fetch files up to 20MB)" if "400" in str(e) else ""
        say(chat, "Print failed: " + str(e) + note
                 + "\nYou should have gotten the insurance, like Jo said.")
    finally:
        for p in (tmp, pdf_tmp):
            if p and os.path.exists(p):
                os.unlink(p)

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
        cpu        = 100
        memory     = 64
        memory_max = 256
      }
    }
  }
}
