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

        # dynamic membership state (invites/joins) — named volume, outside
        # the repo and outside the job spec; survives redeploys
        mount {
          type   = "volume"
          target = "/data"
          source = "[[ var "state_volume" . ]]"
        }
      }

      template {
        destination = "secrets/bot.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
          {{/* Secret lives in Nomad Variables, not in the job spec: nomad var
               put nomad/jobs/printbot telegram_token=... Rendered by
               consul-template at task start, so `nomad job inspect` shows this
               template rather than the token itself. */}}
          {{ with nomadVar "nomad/jobs/printbot" }}
          TELEGRAM_TOKEN="{{ .telegram_token }}"
          {{ end }}
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
import json, os, re, secrets as pysecrets, subprocess, tempfile, threading, time, urllib.request, urllib.parse

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

BASE_ALLOWED = {s.strip() for s in os.environ.get("ALLOWED_CHAT_IDS", "").split(",") if s.strip()}
STATE_FILE = "/data/members.json"
STATE_LOCK = threading.Lock()

def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"members": {}, "invites": {}}

def save_state(st):
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f)
    os.replace(tmp, STATE_FILE)

def allowed_ids():
    return BASE_ALLOWED | set(load_state()["members"].keys())

def is_allowed(chat):
    return chat in allowed_ids()
CUPS = os.environ["CUPS_SERVER"]
PRINTER = os.environ["PRINTER"]
GOTENBERG = os.environ.get("GOTENBERG", "")
INK_URL = os.environ.get("INK_URL", "http://100.116.81.88/ink.json")
ESCL = os.environ.get("ESCL_URL", "http://100.116.81.88:60000/eSCL")

SCAN_XML = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<scan:ScanSettings xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03"'
    ' xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">'
    '<pwg:Version>2.0</pwg:Version>'
    '<pwg:ScanRegions><pwg:ScanRegion>'
    '<pwg:XOffset>0</pwg:XOffset><pwg:YOffset>0</pwg:YOffset>'
    '<pwg:Width>2550</pwg:Width><pwg:Height>3508</pwg:Height>'
    '<pwg:ContentRegionUnits>escl:ThreeHundredthsOfInches</pwg:ContentRegionUnits>'
    '</pwg:ScanRegion></pwg:ScanRegions>'
    '<pwg:InputSource>Platen</pwg:InputSource>'
    '<scan:ColorMode>RGB24</scan:ColorMode>'
    '<scan:XResolution>300</scan:XResolution>'
    '<scan:YResolution>300</scan:YResolution>'
    '<pwg:DocumentFormat>image/jpeg</pwg:DocumentFormat>'
    '</scan:ScanSettings>')
OK_MIME = ("application/pdf", "image/jpeg", "image/png", "text/plain")
CONVERT_EXT = (".docx", ".doc", ".odt", ".xlsx", ".xls", ".ods",
               ".pptx", ".ppt", ".odp", ".rtf")

def api(method, **params):
    data = urllib.parse.urlencode(params).encode()
    with urllib.request.urlopen(API + "/" + method, data, timeout=70) as r:
        return json.load(r)

def plain(chat, text):
    """For replies to chats that are not allowed — no keyboard, because the
    menu belongs to customers and a stranger should get a flat refusal."""
    try:
        api("sendMessage", chat_id=chat, text=text)
    except Exception:
        pass


def note(chat, text, mid=None):
    """Every reply is a card carrying the menu, so no message is a dead end.
    Pass mid to rewrite an earlier card rather than stack a new one."""
    r = card(chat, text, kb(pb_menu_rows()), mid)
    if mid:
        return mid
    return ((r or {}).get("result") or {}).get("message_id")

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

def watch_job(chat, job, name, mid=None):
    try:
        watch_job_inner(chat, job, name, mid)
    except Exception as e:
        print("watcher error:", e, flush=True)

def watch_job_inner(chat, job, name, mid=None):
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
                note(chat, OK + " <b>Printed</b> — " + esc(name)
                           + "\n<i>And it didn't even catch fire.</i>", mid)
            else:
                note(chat, BAD + " <b>Rejected</b> — " + esc(name)
                           + "\n<i>Sabre's official position is that this is a "
                             "feature. Try Status, or a different format.</i>", mid)
            return
        if not nudged and i >= 11:
            note(chat, WARN + " <b>Printer appears to be off</b> — " + esc(name)
                       + "\n<i>Safely queued; prints the moment it wakes up. "
                         "A Sabre product never forgets. Unlike Creed.</i>", mid)
            nudged = True
    note(chat, WARN + " <b>" + esc(name) + "</b> is now Dunder Mifflin's problem."
               + "\n<i>Twelve hours is a long time, even for Sabre.</i>", mid)


def pb_menu_rows():
    row1 = [ {"text": "\U0001f5a8 Status", "callback_data": "pb:status"},
             {"text": "\U0001f58b Ink",    "callback_data": "pb:ink"} ]
    row2 = [ {"text": "\U0001f9f9 Clear queue", "callback_data": "pb:clear"},
             {"text": "\U0001f4e0 Scan",        "callback_data": "pb:scan"} ]
    return [ row1, row2 ]


def pb_view_status():
    try:
        q = queue_status()
    except Exception as e:
        return WARN + " couldn't reach the queue: " + esc(str(e)[:60]), kb(pb_menu_rows())
    idle = "idle" in q.lower() or "empty" in q.lower()
    head = (OK if idle else WARN) + " <b>Sabre Quality Assurance</b>"
    return head + "\n\n<pre>" + esc(q[:1500]) + "</pre>", kb(pb_menu_rows())


def pb_view_ink():
    import urllib.request, json as _json, time as _time, datetime as _dt
    try:
        with urllib.request.urlopen(INK_URL, timeout=15) as r:
            d = _json.load(r)
    except Exception as e:
        return WARN + " ink check failed: " + esc(str(e)[:60]), kb(pb_menu_rows())
    lines = [ "\U0001f58b <b>Sabre Ink Audit</b>", "" ]
    for sup in d.get("supplies", []):
        pct = int(sup.get("percent", 0))
        # low ink is the failure here, so the traffic light is inverted
        mark = OK if pct > 30 else (WARN if pct > 10 else BAD)
        lines.append("<code>" + esc(sup.get("name", "?")[:18]).ljust(18) + " " +
                     bar(pct) + " " + str(pct).rjust(3) + "%</code> " + mark)
    upd = d.get("updated", "")
    stale = ""
    try:
        t = _dt.datetime.fromisoformat(upd)
        age = _time.time() - t.timestamp()
        stale = ago(age)
        if age > 7 * 86400:
            stale = stale + " " + WARN
    except Exception:
        stale = esc(upd or "unknown")
    lines.append("")
    lines.append("<i>reading " + stale + "</i>")
    return "\n".join(lines), kb(pb_menu_rows())


def pb_render(action):
    if action == "pb:ink":
        return pb_view_ink()
    if action == "pb:clear":
        try:
            subprocess.run(["cancel", "-h", CUPS, "-a", PRINTER], timeout=15)
            note = OK + " queue cleared. A Sabre product never forgets, but it does forgive."
        except Exception as e:
            note = WARN + " " + esc(str(e)[:60])
        t, k = pb_view_status()
        return note + "\n\n" + t, k
    return pb_view_status()


def handle(msg):
    chat = str(msg["chat"]["id"])
    text = msg.get("text", "")
    name = (msg.get("from") or {}).get("first_name", "someone")
    if text.startswith("/join"):
        if is_allowed(chat):
            note(chat, OK + " You're already a valued Sabre customer.")
            return
        m = re.search(r"/join\s+(\S+)", text)
        code = m.group(1) if m else ""
        with STATE_LOCK:
            st = load_state()
            inv = st["invites"].get(code)
            if not inv or inv["expires"] < time.time():
                plain(chat, "That invite code is invalid or expired. "
                            "Ask a Sabre customer for a fresh /invite.")
                return
            del st["invites"][code]
            st["members"][chat] = {"name": name, "invited_by": inv["by"],
                                   "joined": time.strftime("%Y-%m-%d")}
            save_state(st)
        note(chat, OK + " <b>Welcome to Sabre Printing Solutions, " + esc(name)
                   + "</b>\n<i>It's pronounced 'SAH-bray.' Send me anything to "
                     "print, or /help for the full suite.</i>")
        broadcast("\U0001f39f <b>" + esc(name) + "</b> (" + esc(chat)
                  + ") joined via invite")
        return
    if not is_allowed(chat):
        plain(chat, "You are not an authorized Sabre customer. "
                 + "This incident will be reported to Jo Bennett. "
                 + "(Your chat id is " + chat + " — an existing customer "
                 + "can /invite you.)")
        return
    if name != "someone":
        with STATE_LOCK:
            st = load_state()
            if st.setdefault("names", {}).get(chat) != name:
                st["names"][chat] = name
                save_state(st)
    if text.startswith("/invite"):
        code = pysecrets.token_urlsafe(6)
        with STATE_LOCK:
            st = load_state()
            st["invites"] = {c: i for c, i in st["invites"].items()
                             if i["expires"] > time.time()}
            st["invites"][code] = {"by": chat, "expires": time.time() + 86400}
            save_state(st)
        note(chat, "\U0001f39f <b>Invite code</b> <i>(24h, single use)</i>\n\n"
                   "<code>" + esc(code) + "</code>\n\n"
                   "<i>Have them message me:</i>  <code>/join " + esc(code) + "</code>")
        return
    if text.startswith("/members"):
        st = load_state()
        nm = st.get("names", {})
        lines = [nm.get(i, "…") + " (" + i + ", vars file)"
                 for i in sorted(BASE_ALLOWED)]
        lines += [nm.get(c, m["name"]) + " (" + c + ", joined " + m["joined"] + ")"
                  for c, m in sorted(st["members"].items())]
        note(chat, "\U0001f465 <b>Sabre Customer Registry</b>\n\n"
                   + "\n".join("• " + esc(l) for l in lines))
        return
    if text.startswith("/revoke"):
        m = re.search(r"/revoke\s+(\S+)", text)
        target = m.group(1) if m else ""
        with STATE_LOCK:
            st = load_state()
            if target in st["members"]:
                gone = st["members"].pop(target)
                save_state(st)
                note(chat, OK + " Revoked <b>" + esc(gone["name"]) + "</b> ("
                           + esc(target) + ")\n<i>Sabre wishes them well in their "
                             "future endeavors.</i>")
            elif target in BASE_ALLOWED:
                note(chat, WARN + " That member is set in the vars file — remove "
                           "them there and redeploy.")
            else:
                note(chat, "<i>Usage:</i> <code>/revoke CHAT_ID</code>  "
                           "<i>(see /members)</i>")
        return
    if text.startswith("/help"):
        note(chat, "\U0001f4cb <b>Sabre Command Suite</b>\n"
                   "<i>(it's pronounced 'SAH-bray')</i>\n\n"
                   "Send any <b>file or photo</b> — prints it\n"
                   "<b>/scan</b> — scan the flatbed, get a JPG\n"
                   "<b>/scan pdf</b> — same, as PDF\n"
                   "<b>/status</b> — queue + printer state\n"
                   "<b>/ink</b> — cartridge levels\n"
                   "<b>/cancel</b> N — cancel job N\n"
                   "<b>/clear</b> — cancel every waiting job\n"
                   "<b>/invite</b> — one-time code to add someone\n"
                   "<b>/members</b> — who's allowed\n"
                   "<b>/revoke</b> ID — remove an invited member")
        return
    if text.startswith("/scan"):
        want_pdf = "pdf" in text
        mid = note(chat, "\U0001f4e0 <b>Sabre Imaging Division</b>\n"
                         "<i>Scanning the platen — place the document face-down. "
                         "This takes about 30 seconds.</i>")
        threading.Thread(target=do_scan, args=(chat, want_pdf, mid), daemon=True).start()
        return
    if text.startswith("/menu"):
        t, k = pb_view_status()
        card(chat, t, k)
        return
    if text.startswith("/status"):
        t, k = pb_view_status()
        card(chat, t, k)
        return
    if text.startswith("/clear"):
        try:
            pending = subprocess.run(["lpstat", "-h", CUPS, "-o"],
                                     capture_output=True, text=True, timeout=15).stdout
            jobs = re.findall(r"^(\S+-\d+)", pending, re.M)
            if not jobs:
                note(chat, OK + " The queue is already empty. Sabre efficiency.")
                return
            failed = []
            for j in jobs:
                r = subprocess.run(["cancel", "-h", CUPS, j],
                                   capture_output=True, text=True, timeout=15)
                if r.returncode != 0:
                    failed.append(j + ": " + r.stderr.strip())
            out = OK + " Canceled <b>" + str(len(jobs) - len(failed)) + "</b> job(s)"
            if failed:
                out += "\n" + WARN + " Couldn't cancel:\n<code>" \
                       + esc("\n".join(failed)) + "</code>"
            note(chat, out)
        except Exception as e:
            note(chat, BAD + " <b>Clear failed</b>\n<code>"
                       + esc(str(e)[:150]) + "</code>")
        return
    if text.startswith("/cancel"):
        m = re.search(r"/cancel\s+(\d+)", text)
        if not m:
            note(chat, "<i>Usage:</i> <code>/cancel N</code>  "
                       "<i>(job number from Status)</i>")
            return
        j = PRINTER + "-" + m.group(1)
        r = subprocess.run(["cancel", "-h", CUPS, j],
                           capture_output=True, text=True, timeout=15)
        note(chat, (OK + " Canceled <b>" + esc(j) + "</b>") if r.returncode == 0
                   else WARN + " Couldn't cancel <b>" + esc(j) + "</b>\n<code>"
                        + esc(r.stderr.strip()[:120]) + "</code>")
        return
    if text.startswith("/ink"):
        t, k = pb_view_ink()
        card(chat, t, k)
        return
    if text.startswith("/start") or (text and not msg.get("document") and not msg.get("photo")):
        note(chat, "\U0001f5a8 <b>Sabre Printing Solutions</b>\n"
                   "<i>It's pronounced 'SAH-bray.'</i>\n\n"
                   "Send a PDF, photo, text file or office doc "
                   "(docx/xlsx/pptx/odt) and it prints on <b>" + esc(PRINTER) + "</b>.\n\n"
                   "<i>Printer off? The job waits — a Sabre product never "
                   "forgets.</i>\n\n<b>/help</b> — all commands")
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
            note(chat, WARN + " <b>Unsupported format</b> — <code>"
                       + esc(str(doc.get("mime_type"))) + "</code>\n"
                       "<i>Our engineers in Tallahassee accept PDF, images, text, "
                       "or office docs (docx/xlsx/pptx/odt…).</i>")
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
        mid = note(chat, "\U0001f5a8 <b>" + esc(name) + "</b>\n<i>"
                         + ("Routing through the Sabre Document Excellence Pipeline™…"
                            if convert else "Sending to the printer…") + "</i>")
        if convert:
            pdf_tmp = to_pdf(tmp, name)
            target = pdf_tmp
        job = print_file(target, name)
        note(chat, "\U0001f5a8 <b>Job " + esc(job.rsplit("-", 1)[-1]) + " accepted</b> — "
                   + esc(name) + "\n<i>It's pronounced 'SAH-bray.'</i>", mid)
        threading.Thread(target=watch_job, args=(chat, job, name, mid), daemon=True).start()
    except Exception as e:
        hint = " (Telegram bots can only fetch files up to 20MB)" if "400" in str(e) else ""
        note(chat, BAD + " <b>Print failed</b>\n<code>" + esc(str(e)[:150] + hint)
                   + "</code>\n<i>You should have gotten the insurance, like Jo said.</i>")
    finally:
        for p in (tmp, pdf_tmp):
            if p and os.path.exists(p):
                os.unlink(p)

def send_document(chat, data, filename):
    boundary = "----sabrescan" + str(int(time.time()))
    body = (("--" + boundary + "\r\n"
             + 'Content-Disposition: form-data; name="chat_id"\r\n\r\n'
             + chat + "\r\n--" + boundary + "\r\n"
             + 'Content-Disposition: form-data; name="document"; filename="' + filename + '"\r\n'
             + "Content-Type: application/octet-stream\r\n\r\n").encode()
            + data + ("\r\n--" + boundary + "--\r\n").encode())
    req = urllib.request.Request(API + "/sendDocument", data=body,
        headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    with urllib.request.urlopen(req, timeout=120) as r:
        r.read()

def do_scan(chat, want_pdf, mid=None):
    try:
        req = urllib.request.Request(ESCL + "/ScanJobs", data=SCAN_XML.encode(),
                                     headers={"Content-Type": "text/xml"})
        with urllib.request.urlopen(req, timeout=30) as r:
            job = r.headers.get("Location", "")
        if not job:
            note(chat, WARN + " <b>The scanner didn't accept the job</b>\n"
                       "<i>Is the printer on?</i>", mid)
            return
        data = None
        for _ in range(15):
            time.sleep(8)
            try:
                with urllib.request.urlopen(job + "/NextDocument", timeout=60) as r:
                    data = r.read()
                break
            except Exception:
                continue
        try:
            urllib.request.urlopen(
                urllib.request.Request(job, method="DELETE"), timeout=10).read()
        except Exception:
            pass
        if not data:
            note(chat, WARN + " <b>Scan timed out</b>\n<i>Lid open, or printer "
                       "asleep? Try again.</i>", mid)
            return
        stamp = time.strftime("%Y%m%d-%H%M")
        if want_pdf and GOTENBERG:
            boundary = "----scanpdf" + str(int(time.time()))
            body = (("--" + boundary + "\r\n"
                     + 'Content-Disposition: form-data; name="files"; filename="scan.jpg"\r\n'
                     + "Content-Type: image/jpeg\r\n\r\n").encode()
                    + data + ("\r\n--" + boundary + "--\r\n").encode())
            req = urllib.request.Request(GOTENBERG + "/forms/libreoffice/convert", data=body,
                headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            send_document(chat, data, "scan-" + stamp + ".pdf")
        else:
            send_document(chat, data, "scan-" + stamp + ".jpg")
        note(chat, OK + " <b>Scan complete</b>\n<i>Sabre Imaging thanks you for "
                   "your business.</i>", mid)
    except Exception as e:
        note(chat, BAD + " <b>Scan failed</b>\n<code>" + esc(str(e)[:150]) + "</code>", mid)

def broadcast(text):
    for c in allowed_ids():
        note(c, text)

def alert_loop():
    # One ping per state change, to every allowed chat. Checks every 30 min.
    state = {}
    while True:
        try:
            with urllib.request.urlopen(INK_URL, timeout=15) as r:
                d = json.load(r)
            # no staleness alert by design: the printer is deliberately
            # unplugged for long stretches; /ink shows the reading's age
            for s in d.get("supplies", []):
                pct, name = s["percent"], s["name"]
                band = "out" if pct <= 5 else "low" if pct <= 15 else "ok"
                if band != state.get(name):
                    if band == "out":
                        broadcast("🛑 Sabre Supply Emergency: " + name + " at "
                                  + str(pct) + "% — replace it now (HP 305). "
                                  + "Jobs will queue but print poorly or not at all.")
                    elif band == "low":
                        broadcast("⚠️ Sabre Supply Notice: " + name + " at "
                                  + str(pct) + "% — time to order an HP 305/305XL.")
                    elif state.get(name) in ("low", "out"):
                        broadcast("✅ " + name + " replaced — back to "
                                  + str(pct) + "%. Sabre thanks you.")
                    state[name] = band
        except Exception as e:
            print("alert loop error:", e, flush=True)
        time.sleep(1800)

def main():
    threading.Thread(target=alert_loop, daemon=True).start()
    offset = 0
    while True:
        try:
            updates = api("getUpdates", offset=offset, timeout=50)
            for u in updates.get("result", []):
                offset = u["update_id"] + 1
                if "callback_query" in u:
                    cq = u["callback_query"]
                    chat = str(cq["message"]["chat"]["id"])
                    if not is_allowed(chat):
                        continue
                    tg("answerCallbackQuery", {"callback_query_id": cq["id"]})
                    if cq.get("data") == "pb:scan":
                        mid = cq["message"]["message_id"]
                        note(chat, "\U0001f4e0 <b>Sabre Imaging Division</b>\n"
                                   "<i>Scanning the platen — place the document "
                                   "face-down. This takes about 30 seconds.</i>", mid)
                        threading.Thread(target=do_scan, args=(chat, False, mid),
                                         daemon=True).start()
                        continue
                    try:
                        t, k = pb_render(cq.get("data", "pb:status"))
                    except Exception as e:
                        t, k = WARN + " " + esc(str(e)[:150]), kb(pb_menu_rows())
                    card(chat, t, k, cq["message"]["message_id"])
                    continue
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
