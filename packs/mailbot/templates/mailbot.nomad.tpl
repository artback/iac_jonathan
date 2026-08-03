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

        # Obsidian vault — bot writes only under /vault/Mail Triage/
        # Stats dir — dashboard nginx serves mailstats.json from here
        volumes = [
          "[[ var "vault_dir" . ]]:/vault",
          "/home/dwight/mailstats:/statsout",
        ]
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
          KEEP_ALIVE="[[ var "keep_alive" . ]]"
          DIGEST_HOUR="[[ var "digest_hour" . ]]"
          CATEGORIES="[[ range $k, $v := (var "categories" .) ]][[ $k ]]=[[ $v ]]|[[ end ]]"
          TRACKED="[[ range $t := (var "tracked" .) ]][[ $t ]],[[ end ]]"
          PROFILE="[[ var "profile" . ]]"
        EOH
      }

      # Read-only triage: the mailbox is opened with SELECT (readonly), so no
      # flag, move, or delete can ever happen. State (last UID, triage log)
      # lives in sqlite on the named volume, which the nightly backup covers.
      template {
        destination = "local/bot.py"
        change_mode = "restart"
        data        = <<EOH
import email, email.header, email.utils, imaplib, json, os, sqlite3, threading, time, urllib.request

HOST = os.environ["IMAP_HOST"]
USER = os.environ["IMAP_USER"]
PASSWORD = os.environ["IMAP_PASSWORD"]
TOKEN = os.environ["TELEGRAM_TOKEN"]
CHAT = os.environ["CHAT_ID"]
OLLAMA = os.environ["OLLAMA_URL"]
MODEL = os.environ["MODEL"]
DIGEST_HOUR = int(os.environ.get("DIGEST_HOUR", "8"))
DB = "/data/mail.db"
CATS = {}
for pair in os.environ.get("CATEGORIES", "").split("|"):
    if "=" in pair:
        k, v = pair.split("=", 1)
        CATS[k.strip()] = v.strip()
if not CATS:
    CATS = {"other": "anything"}
TRACKED = {t.strip() for t in os.environ.get("TRACKED", "").split(",") if t.strip()}
PROFILE = os.environ.get("PROFILE", "")
VAULT = "/vault/Mail Triage"
MAX_LLM_PER_CYCLE = 10
DRAIN_PER_CYCLE = 30  # history is batched, so a bigger bite fits the same time
KEEP_ALIVE = os.environ.get("KEEP_ALIVE", "30s")
STAGES = ("outreach", "applied", "interview", "rejected", "offer", "update")
ICONS = {"urgent": "🚨", "job": "💼", "finance": "💶", "personal": "💬",
         "orders": "📦", "travel": "✈️", "newsletter": "📰", "marketing": "🔇",
         "other": "✉️"}
NOISE = {"newsletter", "marketing"}
EXTRACT_SCHEMAS = {
    "orders": '{"carrier": string, "tracking_number": string or empty, "eta": string or empty, "merchant": string}',
    "travel": '{"mode": one of [flight,train,bus,ferry], "carrier": string, "number": string, "date": string, "from": string, "to": string, "reference": string or empty}',
    "finance": '{"payee": string, "amount": string or empty, "due_date": string or empty}',
}

def db():
    c = sqlite3.connect(DB)
    c.execute("CREATE TABLE IF NOT EXISTS mail (uid INTEGER PRIMARY KEY, ts INTEGER, "
              "sender TEXT, subject TEXT, category TEXT, importance TEXT, summary TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS leads (key TEXT PRIMARY KEY, ts INTEGER, "
              "company TEXT, role TEXT, location TEXT, deadline TEXT, stage TEXT, "
              "score INTEGER, reason TEXT, summary TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS extracts (uid INTEGER PRIMARY KEY, ts INTEGER, "
              "kind TEXT, data TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS noise (sender TEXT PRIMARY KEY, count INTEGER, "
              "last_ts INTEGER, unsub TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS pending (uid INTEGER PRIMARY KEY, ts INTEGER, "
              "sender TEXT, subject TEXT, body TEXT)")
    return c

def meta_get(c, k, default=""):
    r = c.execute("SELECT v FROM meta WHERE k=?", (k,)).fetchone()
    return r[0] if r else default

def meta_set(c, k, v):
    c.execute("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v=excluded.v", (k, str(v)))
    c.commit()

def say_to(chat, text):
    try:
        req = urllib.request.Request(
            "https://api.telegram.org/bot" + TOKEN + "/sendMessage",
            data=json.dumps({"chat_id": chat, "text": text}).encode(),
            headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=30).read()
    except Exception as e:
        print("say error:", e, flush=True)

def say(text):
    say_to(CHAT, text)

def safe_decode(raw, charset):
    """Bytes -> str, tolerating the charset labels mail servers invent
    ('unknown-8bit', 'x-unknown', misspellings). Never raises."""
    for enc in (charset, "utf-8", "latin-1"):
        if not enc:
            continue
        try:
            return raw.decode(enc, "replace")
        except (LookupError, TypeError):
            continue
    return raw.decode("utf-8", "replace")

def decode(value):
    if not value:
        return ""
    try:
        parts = email.header.decode_header(value)
    except Exception:
        return str(value).strip()
    out = ""
    for txt, enc in parts:
        out += safe_decode(txt, enc) if isinstance(txt, bytes) else txt
    return out.strip()

def body_text(msg):
    try:
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == "text/plain":
                    raw = part.get_payload(decode=True)
                    if raw:
                        return safe_decode(raw, part.get_content_charset())
            return ""
        raw = msg.get_payload(decode=True)
        return safe_decode(raw, msg.get_content_charset()) if raw else ""
    except Exception:
        return ""

def llm(prompt):
    # keep_alive is short on purpose: the 3B model holds ~2.5GB resident, and
    # this Pi runs ~20 other services. Ollama's 5-minute default plus 2-minute
    # polling would pin that RAM permanently; 30s frees it between bursts at
    # the price of a few seconds' reload.
    req = urllib.request.Request(OLLAMA + "/api/generate",
        data=json.dumps({"model": MODEL, "stream": False, "format": "json",
                         "keep_alive": KEEP_ALIVE, "prompt": prompt}).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.loads(json.load(r)["response"])

TRANSACTIONAL = ("order", "commande", "shipping", "shipped", "shipment", "dispatch",
                 "parcel", "package", "colis", "expédi", "tracking", "suivi",
                 "delivery", "delivered", "livraison", "invoice", "facture",
                 "receipt", "reçu", "payment", "paiement", "refund", "remboursement",
                 "flight", "vol ", "booking", "réservation", "boarding", "check-in",
                 "billet", "ticket", "itinerary", "reservation", "confirmation",
                 "appointment", "rendez-vous", "due", "échéance", "statement")

def prefilter(msg, sender, subject):
    """Skip the LLM for obvious bulk mail. Returns a category or None.

    Bulk senders set List-Unsubscribe; transactional mail sometimes does too,
    so anything whose subject looks like an order/travel/payment still goes
    to the model. This typically removes half the inbox from the LLM path."""
    if not msg.get("List-Unsubscribe"):
        return None
    hay = (subject + " " + sender).lower()
    if any(word in hay for word in TRANSACTIONAL):
        return None
    precedence = (msg.get("Precedence") or "").lower()
    if precedence in ("bulk", "list") or msg.get("List-Id"):
        return "newsletter"
    return "marketing"

def classify(sender, subject, body):
    cat_lines = "\n".join("- " + k + ": " + v for k, v in CATS.items())
    result = llm("Classify this email into exactly one category:\n" + cat_lines
                 + '\n\nReply ONLY with JSON: {"category": "<name>", '
                 '"importance": one of [high,normal,low], '
                 '"summary": one sentence max 15 words}.'
                 + "\n\nFrom: " + sender + "\nSubject: " + subject
                 + "\nBody: " + body[:1500])
    cat = result.get("category") if result.get("category") in CATS else "other"
    imp = result.get("importance") if result.get("importance") in ("high", "normal", "low") else "normal"
    summary = str(result.get("summary") or subject)[:200]
    return cat, imp, summary

def extract(c, uid, kind, sender, subject, body):
    schema = EXTRACT_SCHEMAS.get(kind)
    if not schema:
        return None
    r = llm("Extract structured details from this email. Reply ONLY with JSON: "
            + schema + ". Use empty strings for anything not stated. Do not invent values."
            + "\n\nFrom: " + sender + "\nSubject: " + subject + "\nBody: " + body[:1500])
    if not isinstance(r, dict):
        return None
    r = {k: str(v)[:80] for k, v in r.items() if v}
    if not r:
        return None
    c.execute("INSERT OR REPLACE INTO extracts (uid, ts, kind, data) VALUES (?,?,?,?)",
              (uid, int(time.time()), kind, json.dumps(r)))
    c.commit()
    return r

def note_noise(c, sender, msg):
    unsub = msg.get("List-Unsubscribe") or ""
    link = ""
    for part in unsub.split(","):
        part = part.strip().strip("<>")
        if part.startswith("http"):
            link = part[:300]
            break
        if part.startswith("mailto:") and not link:
            link = part[:300]
    addr = sender.split("<")[-1].rstrip(">").strip() or sender
    c.execute("INSERT INTO noise (sender, count, last_ts, unsub) VALUES (?,1,?,?) "
              "ON CONFLICT(sender) DO UPDATE SET count = noise.count + 1, "
              "last_ts = excluded.last_ts, unsub = CASE WHEN excluded.unsub != '' "
              "THEN excluded.unsub ELSE noise.unsub END",
              (addr, int(time.time()), link))
    c.commit()

def logistics(c):
    now = int(time.time())
    rows = c.execute("SELECT kind, data, ts FROM extracts WHERE ts > ? ORDER BY ts DESC",
                     (now - 45 * 86400,)).fetchall()
    packages, travel, bills = [], [], []
    for kind, data, ts in rows:
        d = json.loads(data)
        if kind == "orders" and d.get("tracking_number"):
            packages.append(d)
        elif kind == "travel" and (d.get("number") or d.get("date")):
            travel.append(d)
        elif kind == "finance" and d.get("due_date"):
            bills.append(d)
    return packages[:10], travel[:10], bills[:10]

def safe_name(s):
    return "".join(ch if ch.isalnum() or ch in " -_" else "_" for ch in s).strip()[:80] or "unknown"

def track_lead(c, sender, subject, body, summary):
    r = llm("You are tracking a job search for this person: " + PROFILE
            + "\nAnalyze this job-related email. Reply ONLY with JSON: "
            '{"company": string, "role": string, "location": string, '
            '"deadline": string or empty, '
            '"stage": one of [outreach,applied,interview,rejected,offer,update], '
            '"fit_score": integer 0-100 for how well it fits the person, '
            '"reason": max 20 words why that score}.'
            + "\n\nFrom: " + sender + "\nSubject: " + subject + "\nBody: " + body[:1500])
    company = str(r.get("company") or "Unknown")[:60]
    role = str(r.get("role") or "Unknown role")[:80]
    stage = r.get("stage") if r.get("stage") in STAGES else "update"
    score = max(0, min(100, int(r.get("fit_score") or 0)))
    key = safe_name(company).lower() + "|" + safe_name(role).lower()
    c.execute("INSERT INTO leads (key, ts, company, role, location, deadline, stage, score, reason, summary) "
              "VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(key) DO UPDATE SET "
              "ts=excluded.ts, stage=excluded.stage, deadline=excluded.deadline, summary=excluded.summary",
              (key, int(time.time()), company, role, str(r.get("location") or "")[:60],
               str(r.get("deadline") or "")[:40], stage, score,
               str(r.get("reason") or "")[:200], summary))
    c.commit()
    note_path = VAULT + "/" + safe_name(company) + " - " + safe_name(role) + ".md"
    stamp = time.strftime("%Y-%m-%d")
    if not os.path.exists(note_path):
        os.makedirs(VAULT, exist_ok=True)
        with open(note_path, "w") as f:
            f.write("---\ncompany: " + company + "\nrole: " + role
                    + "\nlocation: " + str(r.get("location") or "") + "\nfit: " + str(score)
                    + "\nstage: " + stage + "\ncreated: " + stamp + "\n---\n\n"
                    + "# " + company + " — " + role + "\n\n"
                    + "Fit " + str(score) + "/100 — " + str(r.get("reason") or "") + "\n\n## Timeline\n")
    with open(note_path, "a") as f:
        f.write("- " + stamp + " **" + stage + "** — " + summary + "\n")
    rebuild_top(c)
    return company, role, stage, score

def rebuild_top(c):
    rows = c.execute("SELECT company, role, location, deadline, stage, score, ts "
                     "FROM leads ORDER BY score DESC").fetchall()
    now = int(time.time())
    week = sum(1 for x in rows if now - x[6] < 7 * 86400)
    by_stage = {}
    for x in rows:
        by_stage[x[4]] = by_stage.get(x[4], 0) + 1
    responded = sum(by_stage.get(s, 0) for s in ("interview", "rejected", "offer"))
    active = sum(1 for x in rows if x[4] not in ("rejected",))
    stats = ("**" + str(len(rows)) + " leads** · " + str(active) + " active · "
             + str(week) + " touched this week · "
             + " / ".join(str(by_stage.get(s, 0)) + " " + s for s in STAGES if by_stage.get(s)))
    if by_stage.get("applied") or responded:
        total_applied = by_stage.get("applied", 0) + responded
        stats += " · response rate " + str(int(100 * responded / max(1, total_applied))) + "%"
    lines = ["# Top Jobs (auto)", "", "> " + stats, "",
             "| Fit | Company | Role | Stage | Deadline |", "|---|---|---|---|---|"]
    for company, role, loc, deadline, stage, score, ts in rows:
        name = safe_name(company) + " - " + safe_name(role)
        wiki_open, wiki_close = "[" + "[", "]" + "]"  # avoid literal pack delimiters
        cell = "~~" + company + "~~" if stage == "rejected" else wiki_open + name + "|" + company + wiki_close
        lines.append("| " + str(score) + " | " + cell + " | " + role + " | "
                     + stage + " | " + (deadline or "—") + " |")
    os.makedirs(VAULT, exist_ok=True)
    with open(VAULT + "/Top Jobs.md", "w") as f:
        f.write("\n".join(lines) + "\n")

def uid_search(imap, criterion):
    """UID search returning a list of ints. Some servers (iCloud) answer a
    no-match search with [None] rather than [b''], hence the guard."""
    _, data = imap.uid("search", None, criterion)
    if not data or not data[0]:
        return []
    return [int(x) for x in data[0].split()]

def poll(c):
    imap = imaplib.IMAP4_SSL(HOST)
    try:
        imap.login(USER, PASSWORD)
        imap.select("INBOX", readonly=True)
        last = meta_get(c, "last_uid")
        if not last:
            # first run: baseline at current newest UID, don't classify backlog
            uids = uid_search(imap, "ALL")
            meta_set(c, "last_uid", uids[-1] if uids else 0)
            say("📬 Mail triage is live — watching " + USER + " from now on.")
            return
        llm_budget = MAX_LLM_PER_CYCLE
        for uid in uid_search(imap, "UID " + str(int(last) + 1) + ":*"):
            if uid <= int(last):
                continue
            if llm_budget <= 0:
                # burst guard: leave the rest for the next cycle so a flood
                # can't monopolise the Pi's CPU (UID cursor stays put)
                print("llm budget spent, resuming next cycle", flush=True)
                break
            _, fetched = imap.uid("fetch", str(uid), "(BODY.PEEK[])")
            raw = fetched[0][1] if fetched and fetched[0] else None
            if not raw:
                meta_set(c, "last_uid", uid)
                continue
            msg = email.message_from_bytes(raw)
            sender = decode(msg.get("From"))
            subject = decode(msg.get("Subject")) or "(no subject)"
            skipped = prefilter(msg, sender, subject)
            if skipped:
                cat, imp, summary = skipped, "low", subject[:200]
                meta_set(c, "llm_skipped", int(meta_get(c, "llm_skipped", "0")) + 1)
            else:
                try:
                    cat, imp, summary = classify(sender, subject, body_text(msg))
                    llm_budget -= 1
                    meta_set(c, "llm_calls", int(meta_get(c, "llm_calls", "0")) + 1)
                except Exception as e:
                    print("classify error:", e, flush=True)
                    cat, imp, summary = "other", "normal", subject
            c.execute("INSERT OR IGNORE INTO mail (uid, ts, sender, subject, category, importance, summary) "
                      "VALUES (?, ?, ?, ?, ?, ?, ?)",
                      (uid, int(time.time()), sender, subject, cat, imp, summary))
            c.commit()
            meta_set(c, "last_uid", uid)
            body = body_text(msg)
            if cat in NOISE:
                note_noise(c, sender, msg)
            elif cat in EXTRACT_SCHEMAS:
                try:
                    got = extract(c, uid, cat, sender, subject, body)
                    if got and cat == "travel":
                        say("✈️ Travel booked: " + " ".join(
                            filter(None, [got.get("carrier"), got.get("number"),
                                          got.get("date"), got.get("from", "") + "→" + got.get("to", "")])))
                    elif got and cat == "orders" and got.get("tracking_number"):
                        say("📦 " + got.get("merchant", "Package") + " shipped — "
                            + got.get("carrier", "") + " " + got["tracking_number"]
                            + (" · ETA " + got["eta"] if got.get("eta") else ""))
                except Exception as e:
                    print("extract error:", e, flush=True)
            if cat in NOISE:
                continue
            if imp == "high" or cat == "urgent":
                say(ICONS.get(cat, "✉️") + " " + cat.upper() + " — " + summary
                    + "\n\nFrom: " + sender + "\nSubject: " + subject)
    finally:
        try:
            imap.logout()
        except Exception:
            pass

def backfill(c, days):
    """Phase 1: sweep history cheaply. Bulk mail is classified from headers
    alone (free); everything else is parked in `pending` for the LLM to drain
    at its own pace. Nothing here calls the model, so it finishes in minutes."""
    imap = imaplib.IMAP4_SSL(HOST)
    scanned = bulk = parked = failed = 0
    try:
        imap.login(USER, PASSWORD)
        imap.select("INBOX", readonly=True)
        since = time.strftime("%d-%b-%Y", time.localtime(time.time() - days * 86400))
        uids = uid_search(imap, "(SINCE " + since + ")")
        known = {r[0] for r in c.execute("SELECT uid FROM mail").fetchall()}
        known |= {r[0] for r in c.execute("SELECT uid FROM pending").fetchall()}
        for uid in uids:
            if uid in known:
                continue
            try:
                _, fetched = imap.uid("fetch", str(uid), "(BODY.PEEK[])")
                if not fetched or not fetched[0]:
                    continue
                msg = email.message_from_bytes(fetched[0][1])
                sender = decode(msg.get("From"))
                subject = decode(msg.get("Subject")) or "(no subject)"
                try:
                    ts = int(time.mktime(email.utils.parsedate(msg.get("Date"))))
                except Exception:
                    ts = int(time.time())
                scanned += 1
                skipped = prefilter(msg, sender, subject)
                if skipped:
                    c.execute("INSERT OR IGNORE INTO mail (uid, ts, sender, subject, category, "
                              "importance, summary) VALUES (?,?,?,?,?,?,?)",
                              (uid, ts, sender, subject, skipped, "low", subject[:200]))
                    note_noise(c, sender, msg)
                    bulk += 1
                else:
                    c.execute("INSERT OR IGNORE INTO pending (uid, ts, sender, subject, body) "
                              "VALUES (?,?,?,?,?)",
                              (uid, ts, sender, subject, body_text(msg)[:1500]))
                    parked += 1
                if scanned % 100 == 0:
                    c.commit()
            except Exception as e:
                # one malformed message must not abort a 1000-message sweep
                failed += 1
                print("backfill skip uid", uid, "-", e, flush=True)
                continue
        c.commit()
    finally:
        try:
            imap.logout()
        except Exception:
            pass
    return scanned, bulk, parked, failed

BATCH = 3

def classify_batch(items):
    """Classify up to BATCH emails in one call from sender+subject alone.

    Measured on a Pi: 27s per email individually, 4.3s per email in threes.
    Batches larger than ~3 make the 3B model lose track of which answer
    belongs to which email (verified: 8-item batches scrambled categories),
    so BATCH stays small and the result count is validated."""
    listing = "\n".join(
        str(i) + ". From: " + s[:60] + " | Subject: " + subj[:90]
        for i, (s, subj) in enumerate(items))
    r = llm('Classify each email. Reply ONLY with JSON '
            '{"results":[{"i":0,"category":"...","importance":"..."}]}. '
            "Categories: " + ",".join(CATS) + ". Importance: high,normal,low.\n\n"
            + listing)
    results = r.get("results") if isinstance(r, dict) else None
    if not isinstance(results, list) or len(results) != len(items):
        raise ValueError("batch misaligned: got " + str(results and len(results)))
    out = []
    for entry in results:
        cat = entry.get("category") if entry.get("category") in CATS else "other"
        imp = entry.get("importance") if entry.get("importance") in ("high", "normal", "low") else "normal"
        out.append((cat, imp))
    return out

def drain_pending(c, budget):
    """Phase 2: classify parked history in small batches, oldest first."""
    rows = c.execute("SELECT uid, ts, sender, subject, body FROM pending "
                     "ORDER BY ts LIMIT ?", (budget,)).fetchall()
    if not rows:
        return
    for start in range(0, len(rows), BATCH):
        chunk = rows[start:start + BATCH]
        try:
            verdicts = classify_batch([(r[2], r[3]) for r in chunk])
            meta_set(c, "llm_calls", int(meta_get(c, "llm_calls", "0")) + 1)
        except Exception as e:
            print("batch failed, falling back to singles:", e, flush=True)
            verdicts = []
            for _, _, sender, subject, body in chunk:
                try:
                    cat, imp, _ = classify(sender, subject, body)
                    verdicts.append((cat, imp))
                except Exception as e2:
                    print("single classify failed:", e2, flush=True)
                    verdicts.append(("other", "normal"))
        for (uid, ts, sender, subject, body), (cat, imp) in zip(chunk, verdicts):
            c.execute("INSERT OR IGNORE INTO mail (uid, ts, sender, subject, category, "
                      "importance, summary) VALUES (?,?,?,?,?,?,?)",
                      (uid, ts, sender, subject, cat, imp, subject[:200]))
            if cat in EXTRACT_SCHEMAS:
                try:
                    extract(c, uid, cat, sender, subject, body)
                except Exception:
                    pass
            c.execute("DELETE FROM pending WHERE uid = ?", (uid,))
        c.commit()
    left = c.execute("SELECT count(*) FROM pending").fetchone()[0]
    if left == 0:
        say("✅ Backfill complete — history fully classified. Try /stats")

def digest(c, force=False):
    today = time.strftime("%Y-%m-%d")
    if not force:
        if time.localtime().tm_hour != DIGEST_HOUR or meta_get(c, "last_digest") == today:
            return
    meta_set(c, "last_digest", today)
    rows = c.execute("SELECT category, summary FROM mail WHERE ts > ? ORDER BY category",
                     (int(time.time()) - 86400,)).fetchall()
    packages, travel, bills = logistics(c)
    if not rows and not packages and not travel:
        return
    by_cat = {}
    noise_count = 0
    for cat, summary in rows:
        if cat in NOISE:
            noise_count += 1
        else:
            by_cat.setdefault(cat, []).append(summary)
    msg = "☕ Morning digest — " + str(len(rows)) + " email" + ("s" if len(rows) != 1 else "") + "\n"
    if travel:
        msg += "\n✈️ UPCOMING TRAVEL\n"
        for t in travel:
            msg += ("• " + " ".join(filter(None, [t.get("carrier"), t.get("number")]))
                    + " " + t.get("date", "") + " " + t.get("from", "")
                    + ("→" + t["to"] if t.get("to") else "")
                    + (" · ref " + t["reference"] if t.get("reference") else "") + "\n")
    if packages:
        msg += "\n📦 PACKAGES IN FLIGHT\n"
        for p in packages:
            msg += ("• " + p.get("merchant", "Order") + " — " + p.get("carrier", "")
                    + " " + p.get("tracking_number", "")
                    + (" · ETA " + p["eta"] if p.get("eta") else "") + "\n")
    if bills:
        msg += "\n💶 DUE SOON\n"
        for b in bills:
            msg += ("• " + b.get("payee", "?") + " " + b.get("amount", "")
                    + " — " + b.get("due_date", "") + "\n")
    for cat in CATS:
        if cat not in by_cat:
            continue
        msg += "\n" + ICONS.get(cat, "✉️") + " " + cat.upper() + "\n"
        for s in by_cat[cat]:
            msg += "• " + s + "\n"
    if noise_count:
        msg += "\n🔇 " + str(noise_count) + " marketing/newsletter email" + ("s" if noise_count != 1 else "") + " ignored\n"
    if time.localtime().tm_wday == 0:
        top_noise = c.execute("SELECT sender, count, unsub FROM noise WHERE last_ts > ? "
                              "ORDER BY count DESC LIMIT 5", (int(time.time()) - 30 * 86400,)).fetchall()
        if top_noise:
            msg += "\n🧹 Weekly cleanup — noisiest senders (30d):\n"
            for s, n, unsub in top_noise:
                msg += "• " + s + " ×" + str(n) + ("\n  " + unsub if unsub else " (no unsubscribe link)") + "\n"
    say(msg[:4000])

def write_stats(c):
    now = int(time.time())
    month = now - 30 * 86400
    rows = c.execute("SELECT ts, sender, category, importance FROM mail WHERE ts > ?",
                     (month,)).fetchall()
    days = {}
    cats = {}
    senders = {}
    urgent7 = 0
    for ts, sender, cat, imp in rows:
        day = time.strftime("%Y-%m-%d", time.localtime(ts))
        days[day] = days.get(day, 0) + 1
        cats[cat] = cats.get(cat, 0) + 1
        addr = sender.split("<")[-1].rstrip(">").strip() or sender
        senders[addr] = senders.get(addr, 0) + 1
        if (imp == "high" or cat == "urgent") and now - ts < 7 * 86400:
            urgent7 += 1
    total = len(rows)
    robots = cats.get("newsletter", 0) + cats.get("marketing", 0)
    top = sorted(senders.items(), key=lambda kv: -kv[1])[:5]
    series = []
    for i in range(13, -1, -1):
        day = time.strftime("%Y-%m-%d", time.localtime(now - i * 86400))
        series.append({"day": day[5:], "count": days.get(day, 0)})
    packages, travel, bills = logistics(c)
    noisy = c.execute("SELECT sender, count, unsub FROM noise WHERE last_ts > ? "
                      "ORDER BY count DESC LIMIT 5", (month,)).fetchall()
    stats = {
        "updated": time.strftime("%Y-%m-%dT%H:%M"),
        "total30d": total,
        "robot_pct": int(100 * robots / total) if total else 0,
        "urgent7d": urgent7,
        "categories": cats,
        "top_senders": [{"sender": s, "count": n} for s, n in top],
        "daily": series,
        "packages": packages,
        "travel": travel,
        "bills": bills,
        "noisiest": [{"sender": s, "count": n, "unsub": u} for s, n, u in noisy],
        "llm_calls": int(meta_get(c, "llm_calls", "0")),
        "llm_skipped": int(meta_get(c, "llm_skipped", "0")),
    }
    os.makedirs("/statsout", exist_ok=True)
    with open("/statsout/mailstats.json.tmp", "w") as f:
        json.dump(stats, f)
    with open("/statsout/mailstats.json.tmp") as src, open("/statsout/mailstats.json", "w") as dst:
        dst.write(src.read())
    os.unlink("/statsout/mailstats.json.tmp")

def fmt_travel(t):
    return ("• " + " ".join(filter(None, [t.get("carrier"), t.get("number")]))
            + " " + t.get("date", "") + " " + t.get("from", "")
            + ("→" + t["to"] if t.get("to") else "")
            + (" · ref " + t["reference"] if t.get("reference") else ""))

def fmt_package(p):
    return ("• " + p.get("merchant", "Order") + " — " + p.get("carrier", "")
            + " " + p.get("tracking_number", "")
            + (" · ETA " + p["eta"] if p.get("eta") else ""))

def command(c, text):
    now = int(time.time())
    packages, travel, bills = logistics(c)
    if text.startswith("/travel"):
        return "✈️ Upcoming travel:\n" + ("\n".join(fmt_travel(t) for t in travel)
                                          if travel else "nothing booked")
    if text.startswith("/packages"):
        return "📦 Packages in flight:\n" + ("\n".join(fmt_package(p) for p in packages)
                                             if packages else "nothing in transit")
    if text.startswith("/bills") or text.startswith("/due"):
        return "💶 Due soon:\n" + ("\n".join(
            "• " + (b.get("payee") or "?") + " " + b.get("amount", "") + " — " + b.get("due_date", "")
            for b in bills) if bills else "nothing pending")
    if text.startswith("/today"):
        rows = c.execute("SELECT category, summary FROM mail WHERE ts > ? ORDER BY category",
                         (now - 86400,)).fetchall()
        if not rows:
            return "Nothing new in the last 24h."
        noise = sum(1 for cat, _ in rows if cat in NOISE)
        out = "📥 Last 24h — " + str(len(rows)) + " emails\n"
        by = {}
        for cat, s in rows:
            if cat not in NOISE:
                by.setdefault(cat, []).append(s)
        for cat in CATS:
            if cat in by:
                out += "\n" + ICONS.get(cat, "✉️") + " " + cat.upper() + "\n"
                out += "".join("• " + s + "\n" for s in by[cat])
        if noise:
            out += "\n🔇 " + str(noise) + " marketing/newsletter ignored"
        return out
    if text.startswith("/noise"):
        rows = c.execute("SELECT sender, count, unsub FROM noise WHERE last_ts > ? "
                         "ORDER BY count DESC LIMIT 10", (now - 30 * 86400,)).fetchall()
        if not rows:
            return "No bulk senders recorded yet."
        return "🧹 Noisiest senders (30d):\n" + "\n".join(
            "• " + s + " ×" + str(n) + ("\n  " + u if u else " (no unsubscribe link)")
            for s, n, u in rows)
    if text.startswith("/search"):
        term = text.split(" ", 1)[1].strip() if " " in text else ""
        if not term:
            return "Usage: /search WORD — looks through subjects and summaries"
        rows = c.execute("SELECT category, subject, summary FROM mail "
                         "WHERE subject LIKE ? OR summary LIKE ? "
                         "ORDER BY ts DESC LIMIT 10", ("%" + term + "%", "%" + term + "%")).fetchall()
        if not rows:
            return "Nothing found for '" + term + "'."
        return "🔎 '" + term + "':\n" + "\n".join(
            ICONS.get(cat, "✉️") + " " + (summary or subj) for cat, subj, summary in rows)
    if text.startswith("/stats"):
        total = c.execute("SELECT count(*) FROM mail WHERE ts > ?", (now - 30 * 86400,)).fetchone()[0]
        cats = c.execute("SELECT category, count(*) FROM mail WHERE ts > ? GROUP BY category "
                         "ORDER BY 2 DESC", (now - 30 * 86400,)).fetchall()
        calls = int(meta_get(c, "llm_calls", "0"))
        skipped = int(meta_get(c, "llm_skipped", "0"))
        saved = int(100 * skipped / (calls + skipped)) if (calls + skipped) else 0
        out = "📊 Last 30 days — " + str(total) + " emails\n"
        out += "".join("• " + ICONS.get(k, "✉️") + " " + k + ": " + str(v) + "\n" for k, v in cats)
        out += "\n🧠 " + str(calls) + " classified by the model, " + str(skipped) \
               + " filtered by header (" + str(saved) + "% CPU saved)"
        return out
    if text.startswith("/backfill"):
        parts = text.split()
        days = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 120
        say("⏳ Sweeping " + str(days) + " days of history (headers only, no model)…")
        scanned, bulk, parked, failed = backfill(c, days)
        eta = max(1, parked * 5 // 60)
        return ("📥 Swept " + str(scanned) + " emails\n"
                "• " + str(bulk) + " classified free from headers (bulk mail)\n"
                "• " + str(parked) + " queued for the model\n"
                + ("• " + str(failed) + " unreadable, skipped\n" if failed else "") + "\n"
                "Stats are usable now — try /stats. The queue drains in the "
                "background, roughly " + str(eta) + " min, and I'll say when it's done.")
    if text.startswith("/pending"):
        n = c.execute("SELECT count(*) FROM pending").fetchone()[0]
        return str(n) + " emails still queued for classification" if n else "Queue empty ✓"
    if text.startswith("/digest"):
        # inline: this connection belongs to the listener thread and sqlite
        # connections cannot be used from another one
        digest(c, force=True)
        return None
    return ("📬 Mail commands:\n"
            "/today — last 24h by category\n"
            "/travel — upcoming trips\n"
            "/packages — parcels in transit\n"
            "/bills — payments due\n"
            "/noise — noisiest senders + unsubscribe links\n"
            "/search WORD — find past mail\n"
            "/stats — 30-day breakdown\n"
            "/digest — send the digest now\n"
            "/backfill [days] — sweep history (default 120)\n"
            "/pending — how much history is left to classify")

def listen():
    """Long-poll for commands. Own token, so no conflict with the other bots."""
    c = db()
    offset = 0
    while True:
        try:
            req = urllib.request.Request(
                "https://api.telegram.org/bot" + TOKEN + "/getUpdates",
                data=json.dumps({"offset": offset, "timeout": 50}).encode(),
                headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=70) as r:
                updates = json.load(r)
            for u in updates.get("result", []):
                offset = u["update_id"] + 1
                msg = u.get("message") or {}
                chat = str((msg.get("chat") or {}).get("id", ""))
                text = (msg.get("text") or "").strip()
                if not text:
                    continue
                if chat != CHAT:
                    say_to(chat, "This mailbox bot is private.")
                    continue
                try:
                    reply = command(c, text)
                    if reply:
                        say(reply[:4000])
                except Exception as e:
                    say("Command failed: " + str(e))
        except Exception as e:
            print("listen error:", e, flush=True)
            time.sleep(5)

def main():
    c = db()
    threading.Thread(target=listen, daemon=True).start()
    while True:
        try:
            poll(c)
        except Exception as e:
            print("poll error:", e, flush=True)
        try:
            # new mail always wins; leftovers of the cycle's budget go to history
            drain_pending(c, DRAIN_PER_CYCLE)
        except Exception as e:
            print("drain error:", e, flush=True)
        try:
            digest(c)
        except Exception as e:
            print("digest error:", e, flush=True)
        try:
            write_stats(c)
        except Exception as e:
            print("stats error:", e, flush=True)
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
