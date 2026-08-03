job "mailbot" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "mailbot-group" {
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

        mount {
          type   = "volume"
          target = "/data"
          source = "[[ var "state_volume" . ]]"
        }
      }

      env {
        TZ = "Europe/Stockholm"
      }

      template {
        destination = "secrets/bot.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
          IMAP_HOST="[[ var "imap_host" . ]]"
          IMAP_USER="[[ var "imap_user" . ]]"
          IMAP_PASSWORD="[[ var "imap_password" . ]]"
          TELEGRAM_TOKEN="[[ var "telegram_token" . ]]"
          CHAT_ID="[[ var "chat_id" . ]]"
          OLLAMA_URL="[[ var "ollama_url" . ]]"
          MODEL="[[ var "model" . ]]"
          DIGEST_HOUR="[[ var "digest_hour" . ]]"
        EOH
      }

      # Read-only triage: the mailbox is opened with SELECT (readonly), so no
      # flag, move, or delete can ever happen. State (last UID, triage log)
      # lives in sqlite on the named volume, which the nightly backup covers.
      template {
        destination = "local/bot.py"
        change_mode = "restart"
        data        = <<EOH
import email, email.header, imaplib, json, os, sqlite3, time, urllib.request

HOST = os.environ["IMAP_HOST"]
USER = os.environ["IMAP_USER"]
PASSWORD = os.environ["IMAP_PASSWORD"]
TOKEN = os.environ["TELEGRAM_TOKEN"]
CHAT = os.environ["CHAT_ID"]
OLLAMA = os.environ["OLLAMA_URL"]
MODEL = os.environ["MODEL"]
DIGEST_HOUR = int(os.environ.get("DIGEST_HOUR", "8"))
DB = "/data/mail.db"
CATS = ("urgent", "job", "finance", "personal", "orders", "newsletter", "other")
ICONS = {"urgent": "🚨", "job": "💼", "finance": "💶", "personal": "💬",
         "orders": "📦", "newsletter": "📰", "other": "✉️"}

def db():
    c = sqlite3.connect(DB)
    c.execute("CREATE TABLE IF NOT EXISTS mail (uid INTEGER PRIMARY KEY, ts INTEGER, "
              "sender TEXT, subject TEXT, category TEXT, importance TEXT, summary TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)")
    return c

def meta_get(c, k, default=""):
    r = c.execute("SELECT v FROM meta WHERE k=?", (k,)).fetchone()
    return r[0] if r else default

def meta_set(c, k, v):
    c.execute("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", (k, str(v)))
    c.commit()

def say(text):
    try:
        req = urllib.request.Request(
            "https://api.telegram.org/bot" + TOKEN + "/sendMessage",
            data=json.dumps({"chat_id": CHAT, "text": text}).encode(),
            headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=30).read()
    except Exception as e:
        print("say error:", e, flush=True)

def decode(value):
    if not value:
        return ""
    parts = email.header.decode_header(value)
    out = ""
    for txt, enc in parts:
        out += txt.decode(enc or "utf-8", "replace") if isinstance(txt, bytes) else txt
    return out.strip()

def body_text(msg):
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                try:
                    return part.get_payload(decode=True).decode(
                        part.get_content_charset() or "utf-8", "replace")
                except Exception:
                    continue
        return ""
    try:
        return msg.get_payload(decode=True).decode(
            msg.get_content_charset() or "utf-8", "replace")
    except Exception:
        return ""

def classify(sender, subject, body):
    prompt = ("Classify this email. Reply ONLY with JSON: "
              '{"category": one of [urgent,job,finance,personal,orders,newsletter,other], '
              '"importance": one of [high,normal,low], '
              '"summary": one sentence max 15 words}.'
              + "\n\nFrom: " + sender + "\nSubject: " + subject
              + "\nBody: " + body[:1500])
    req = urllib.request.Request(OLLAMA + "/api/generate",
        data=json.dumps({"model": MODEL, "stream": False, "format": "json",
                         "prompt": prompt}).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        result = json.loads(json.load(r)["response"])
    cat = result.get("category") if result.get("category") in CATS else "other"
    imp = result.get("importance") if result.get("importance") in ("high", "normal", "low") else "normal"
    summary = str(result.get("summary") or subject)[:200]
    return cat, imp, summary

def poll(c):
    imap = imaplib.IMAP4_SSL(HOST)
    try:
        imap.login(USER, PASSWORD)
        imap.select("INBOX", readonly=True)
        last = meta_get(c, "last_uid")
        if not last:
            # first run: baseline at current newest UID, don't classify backlog
            _, data = imap.uid("search", None, "ALL")
            uids = data[0].split()
            meta_set(c, "last_uid", int(uids[-1]) if uids else 0)
            say("📬 Mail triage is live — watching " + USER + " from now on.")
            return
        _, data = imap.uid("search", None, "UID " + str(int(last) + 1) + ":*")
        for uid_b in data[0].split():
            uid = int(uid_b)
            if uid <= int(last):
                continue
            _, fetched = imap.uid("fetch", str(uid), "(BODY.PEEK[])")
            raw = fetched[0][1] if fetched and fetched[0] else None
            if not raw:
                meta_set(c, "last_uid", uid)
                continue
            msg = email.message_from_bytes(raw)
            sender = decode(msg.get("From"))
            subject = decode(msg.get("Subject")) or "(no subject)"
            try:
                cat, imp, summary = classify(sender, subject, body_text(msg))
            except Exception as e:
                print("classify error:", e, flush=True)
                cat, imp, summary = "other", "normal", subject
            c.execute("INSERT OR IGNORE INTO mail (uid, ts, sender, subject, category, importance, summary) "
                      "VALUES (?, ?, ?, ?, ?, ?, ?)",
                      (uid, int(time.time()), sender, subject, cat, imp, summary))
            c.commit()
            meta_set(c, "last_uid", uid)
            if imp == "high" or cat == "urgent":
                say(ICONS.get(cat, "✉️") + " " + cat.upper() + " — " + summary
                    + "\n\nFrom: " + sender + "\nSubject: " + subject)
    finally:
        try:
            imap.logout()
        except Exception:
            pass

def digest(c):
    today = time.strftime("%Y-%m-%d")
    if time.localtime().tm_hour != DIGEST_HOUR or meta_get(c, "last_digest") == today:
        return
    meta_set(c, "last_digest", today)
    rows = c.execute("SELECT category, summary FROM mail WHERE ts > ? ORDER BY category",
                     (int(time.time()) - 86400,)).fetchall()
    if not rows:
        return
    by_cat = {}
    for cat, summary in rows:
        by_cat.setdefault(cat, []).append(summary)
    msg = "☕ Morning mail digest — " + str(len(rows)) + " email" + ("s" if len(rows) > 1 else "") + "\n"
    for cat in CATS:
        if cat not in by_cat:
            continue
        msg += "\n" + ICONS[cat] + " " + cat.upper() + "\n"
        for s in by_cat[cat]:
            msg += "• " + s + "\n"
    say(msg[:4000])

def main():
    c = db()
    while True:
        try:
            poll(c)
        except Exception as e:
            print("poll error:", e, flush=True)
        try:
            digest(c)
        except Exception as e:
            print("digest error:", e, flush=True)
        time.sleep(120)

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
