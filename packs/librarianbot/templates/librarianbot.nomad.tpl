job "librarianbot" {
  datacenters = [[ var "datacenters" . | toStringList ]]
  type        = "service"

  group "librarianbot-group" {
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

      env {
        TZ = "Europe/Stockholm"
      }

      template {
        destination = "secrets/bot.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
          TELEGRAM_TOKEN="{{ with nomadVar "nomad/jobs/librarianbot" }}{{ .telegram_token }}{{ end }}"
          CHAT_ID="[[ var "chat_id" . ]]"
          CALIBRE_URL="[[ var "calibre_url" . ]]"
          CALIBRE_USER="[[ var "calibre_user" . ]]"
          CALIBRE_PASSWORD="{{ with nomadVar "nomad/jobs/librarianbot" }}{{ .calibre_password }}{{ end }}"
          SILENT="[[ var "silent" . ]]"
        EOH
      }

      # Outbound only: long-polls Telegram, talks to Calibre-Web over HTTPS.
      # Nothing listens, nothing is exposed.
      template {
        destination = "local/bot.py"
        change_mode = "restart"
        data        = <<EOH
import html, html.parser, http.cookiejar, json, os, re, time, urllib.parse, urllib.request, uuid, zipfile
from io import BytesIO

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

CHAT = os.environ["CHAT_ID"]
CW = os.environ["CALIBRE_URL"].rstrip("/")
CW_USER = os.environ["CALIBRE_USER"]
CW_PASS = os.environ["CALIBRE_PASSWORD"]
SILENT = os.environ.get("SILENT", "true").lower() != "false"
BOOK_EXT = (".epub", ".pdf", ".mobi", ".azw3", ".azw", ".cbz", ".cbr", ".fb2", ".txt")

def say(text):
    try:
        req = urllib.request.Request(API + "/sendMessage",
            data=json.dumps({"chat_id": CHAT, "text": text,
                             "disable_notification": SILENT}).encode(),
            headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=30).read()
    except Exception as e:
        print("say error:", e, flush=True)

# ---------------------------------------------------------------- Calibre-Web

class Calibre:
    """Session-based client. Calibre-Web has no upload API, so this drives the
    same login + multipart form a browser would."""

    def __init__(self):
        self.opener = None

    def login(self):
        cj = http.cookiejar.CookieJar()
        op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
        op.addheaders = [("User-Agent", "Mozilla/5.0 (librarianbot)")]
        page = op.open(CW + "/login", timeout=30).read().decode("utf-8", "replace")
        token = self.csrf(page)
        body = urllib.parse.urlencode({
            "username": CW_USER, "password": CW_PASS,
            "csrf_token": token or "", "remember_me": "on", "submit": ""}).encode()
        resp = op.open(urllib.request.Request(CW + "/login", data=body), timeout=30)
        text = resp.read().decode("utf-8", "replace")
        if "/logout" not in text and "Books" not in text:
            raise RuntimeError("Calibre-Web rejected the login")
        self.opener = op
        return op

    @staticmethod
    def csrf(page):
        m = re.search(r'name="csrf_token"[^>]*value="([^"]+)"', page)
        return m.group(1) if m else ""

    def upload(self, data, filename):
        if self.opener is None:
            self.login()
        # the upload form carries its own CSRF token
        page = self.opener.open(CW + "/", timeout=30).read().decode("utf-8", "replace")
        token = self.csrf(page)
        boundary = "----librarian" + uuid.uuid4().hex
        parts = []
        if token:
            parts.append(('--' + boundary + '\r\n'
                          'Content-Disposition: form-data; name="csrf_token"\r\n\r\n'
                          + token + '\r\n').encode())
        parts.append(('--' + boundary + '\r\n'
                      'Content-Disposition: form-data; name="btn-upload"; filename="'
                      + filename.replace('"', "") + '"\r\n'
                      'Content-Type: application/octet-stream\r\n\r\n').encode())
        parts.append(data)
        parts.append(('\r\n--' + boundary + '--\r\n').encode())
        payload = b"".join(parts)
        req = urllib.request.Request(CW + "/upload", data=payload, headers={
            "Content-Type": "multipart/form-data; boundary=" + boundary,
            "Referer": CW + "/"})
        resp = self.opener.open(req, timeout=180)
        return resp.status

CAL = Calibre()

# ------------------------------------------------------------ article capture

SKIP_TAGS = {"script", "style", "nav", "footer", "aside", "header", "form",
             "noscript", "svg", "button", "figure", "iframe"}
KEEP_TAGS = {"p", "h1", "h2", "h3", "h4", "li", "blockquote", "pre"}

class Article(html.parser.HTMLParser):
    """Deliberately small: keep block-level text, drop the page furniture.
    Not as good as a real readability port, but dependency-free and it copes
    with the ordinary article layouts people actually share."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth_skip = 0
        self.tag = None
        self.buf = []
        self.blocks = []
        self.title = ""
        self.in_title = False

    def handle_starttag(self, tag, attrs):
        if tag in SKIP_TAGS:
            self.depth_skip += 1
        elif tag == "title":
            self.in_title = True
        elif tag in KEEP_TAGS and not self.depth_skip:
            self.tag = tag
            self.buf = []
        elif tag == "br" and self.tag:
            self.buf.append(" ")

    def handle_endtag(self, tag):
        if tag in SKIP_TAGS and self.depth_skip:
            self.depth_skip -= 1
        elif tag == "title":
            self.in_title = False
        elif tag == self.tag:
            text = re.sub(r"\s+", " ", "".join(self.buf)).strip()
            if len(text) > 1:
                self.blocks.append((tag, text))
            self.tag = None
            self.buf = []

    def handle_data(self, data):
        if self.in_title and not self.title:
            self.title = data.strip()
        elif self.tag and not self.depth_skip:
            self.buf.append(data)

def fetch_article(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Safari/537.36",
        "Accept-Language": "en,fr;q=0.8,sv;q=0.6"})
    with urllib.request.urlopen(req, timeout=60) as r:
        charset = r.headers.get_content_charset() or "utf-8"
        raw = r.read(4_000_000)
    try:
        page = raw.decode(charset, "replace")
    except LookupError:
        page = raw.decode("utf-8", "replace")
    parser = Article()
    parser.feed(page)
    blocks = parser.blocks
    # a page with almost no prose is usually a paywall or a JS shell
    words = sum(len(t.split()) for _tag, t in blocks)
    return parser.title or url, blocks, words

def build_epub(title, blocks, source_url):
    def esc(s):
        return html.escape(s, quote=False)
    body = ""
    for tag, text in blocks:
        t = "h2" if tag in ("h1", "h2", "h3", "h4") else ("li" if tag == "li" else "p")
        body += "<" + t + ">" + esc(text) + "</" + t + ">\n"
    doc = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<!DOCTYPE html>\n'
           '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
           '<meta charset="utf-8"/><title>' + esc(title) + '</title></head><body>'
           '<h1>' + esc(title) + '</h1>\n' + body +
           '<hr/><p><small>' + esc(source_url) + '</small></p>'
           '</body></html>')
    nav = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<html xmlns="http://www.w3.org/1999/xhtml" '
           'xmlns:epub="http://www.idpf.org/2007/ops"><head>'
           '<meta charset="utf-8"/><title>Contents</title></head><body>'
           '<nav epub:type="toc" id="toc"><ol><li>'
           '<a href="article.xhtml">' + esc(title) + '</a></li></ol></nav>'
           '</body></html>')
    uid = "urn:uuid:" + str(uuid.uuid4())
    opf = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
           'unique-identifier="bookid"><metadata '
           'xmlns:dc="http://purl.org/dc/elements/1.1/">'
           '<dc:identifier id="bookid">' + uid + '</dc:identifier>'
           '<dc:title>' + esc(title) + '</dc:title>'
           '<dc:language>en</dc:language>'
           '<dc:source>' + esc(source_url) + '</dc:source>'
           '<meta property="dcterms:modified">'
           + time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + '</meta>'
           '</metadata><manifest>'
           '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
           '<item id="art" href="article.xhtml" media-type="application/xhtml+xml"/>'
           '</manifest><spine><itemref idref="art"/></spine></package>')
    container = ('<?xml version="1.0" encoding="utf-8"?>\n'
                 '<container version="1.0" '
                 'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                 '<rootfiles><rootfile full-path="OEBPS/content.opf" '
                 'media-type="application/oebps-package+xml"/></rootfiles></container>')
    buf = BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        # mimetype must be first and stored uncompressed
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip",
                   compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", container)
        z.writestr("OEBPS/content.opf", opf)
        z.writestr("OEBPS/nav.xhtml", nav)
        z.writestr("OEBPS/article.xhtml", doc)
    return buf.getvalue()

def safe_filename(title):
    name = re.sub(r"[^\w\s.-]", "", title, flags=re.UNICODE).strip()
    name = re.sub(r"\s+", " ", name)[:80] or "article"
    return name + ".epub"

# ------------------------------------------------------------------ handlers

URL_RE = re.compile(r"https?://[^\s<>\"']+")

def handle_url(url):
    say("Fetching " + url[:70] + " …")
    title, blocks, words = fetch_article(url)
    if words < 120:
        say("That page had almost no readable text (" + str(words) + " words) — "
            "probably a paywall or a JavaScript-rendered site. Nothing uploaded.")
        return
    epub = build_epub(title, blocks, url)
    CAL.upload(epub, safe_filename(title))
    say("Added: " + title[:80] + "\n" + str(words) + " words · now in Calibre-Web, "
        "pull it from the OPDS catalogue on the Kindle.")

def handle_file(doc):
    name = doc.get("file_name", "book")
    if not name.lower().endswith(BOOK_EXT):
        say("I can take " + ", ".join(BOOK_EXT) + " — not " + name)
        return
    info = json.load(urllib.request.urlopen(
        API + "/getFile?file_id=" + urllib.parse.quote(doc["file_id"]), timeout=30))
    path = info["result"]["file_path"]
    with urllib.request.urlopen(
            "https://api.telegram.org/file/bot" + TOKEN + "/" + path, timeout=300) as r:
        data = r.read()
    CAL.upload(data, name)
    say("Added: " + name + "\nIt is in Calibre-Web now — pull it from the OPDS "
        "catalogue on the Kindle.")


def lb_menu_rows():
    # A url button is the one thing a phone genuinely wants here: tap through
    # to the catalogue instead of copying an address out of a chat message.
    row1 = [ {"text": "\U0001f4da Open Calibre-Web", "url": CW} ]
    row2 = [ {"text": "\U0001f504 Check", "callback_data": "lb:status"} ]
    return [ row1, row2 ]


def lb_view_status():
    import urllib.request as _u
    lines = [ "\U0001f4d6 <b>Librarian</b>", "" ]
    try:
        req = _u.Request(CW, headers={"User-Agent": "librarianbot"})
        with _u.urlopen(req, timeout=12) as r:
            code = r.getcode()
        lines.append(OK + " Calibre-Web reachable (HTTP " + str(code) + ")")
    except Exception as e:
        lines.append(BAD + " Calibre-Web unreachable — " + esc(str(e)[:60]))
    lines.append("")
    lines.append("Send a <b>link</b> and it becomes an EPUB.")
    lines.append("Send an <b>ebook file</b> and it gets filed.")
    lines.append("<i>Either way it reaches the Kindle over OPDS.</i>")
    return "\n".join(lines), kb(lb_menu_rows())


def handle(msg):
    chat = str(msg["chat"]["id"])
    if chat != CHAT:
        return
    text = (msg.get("text") or msg.get("caption") or "").strip()
    doc = msg.get("document")
    try:
        if doc:
            handle_file(doc)
            return
        if text.startswith("/menu") or text.startswith("/status") or text.startswith("/start"):
            t, k = lb_view_status()
            card(CHAT, t, k)
            return
        m = URL_RE.search(text)
        if m:
            handle_url(m.group(0))
            return
        say("Send me a link and I will turn it into an EPUB, or send an ebook "
            "file and I will file it. Either way it lands in Calibre-Web and "
            "reaches the Kindle through the OPDS catalogue.")
    except Exception as e:
        # a stale session is the usual cause; drop it so the next try re-logs in
        CAL.opener = None
        say("That failed: " + str(e)[:200])

def main():
    offset = 0
    while True:
        try:
            req = urllib.request.Request(API + "/getUpdates",
                data=json.dumps({"offset": offset, "timeout": 50}).encode(),
                headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=70) as r:
                updates = json.load(r)
            for u in updates.get("result", []):
                offset = u["update_id"] + 1
                if "callback_query" in u:
                    cq = u["callback_query"]
                    if str(cq["message"]["chat"]["id"]) != CHAT:
                        continue
                    tg("answerCallbackQuery", {"callback_query_id": cq["id"]})
                    t, k = lb_view_status()
                    card(CHAT, t, k, cq["message"]["message_id"])
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
        cpu        = 200
        memory     = 96
        memory_max = 256
      }
    }
  }
}
