#!/usr/bin/env python3
"""Register each bot's command list and ☰ menu button with Telegram.

Telegram stores these server-side, so they survive clearing the chat, deleting
messages, or restarting the bot — which is the point. An inline keyboard lives
inside one message and dies with it; this does not.

Re-run after changing a bot's commands or rotating its token:

    . ~/.config/homelab/env.sh && python3 scripts/register-bot-commands.py

Tokens are read from Nomad Variables, so nothing secret lives in this file.
"""
import json, os, subprocess, sys, urllib.request

COMMANDS = {
    "homelab-bot": [
        ("menu", "Status card with buttons"),
        ("status", "Cluster summary"),
        ("jobs", "Every job and its state"),
        ("usage", "CPU, memory, disk"),
        ("backup", "Newest database dump"),
        ("logs", "Logs for a job"),
    ],
    "printbot": [
        ("menu", "Printer card with buttons"),
        ("status", "Queue and printer state"),
        ("ink", "Cartridge levels"),
        ("scan", "Scan a page"),
        ("clear", "Cancel every waiting job"),
        ("help", "All commands"),
    ],
    "mediabot": [
        ("menu", "Media card with buttons"),
        ("queue", "Current downloads"),
        ("upcoming", "Next 7 days"),
        ("disk", "Seedbox storage"),
        ("movie", "Search and add a film"),
        ("series", "Search and add a series"),
    ],
    "librarianbot": [
        ("menu", "Library card with buttons"),
        ("status", "Calibre-Web reachability"),
    ],
}


def token_for(job):
    r = subprocess.run(["nomad", "var", "get", "-out=json", "nomad/jobs/" + job],
                       capture_output=True, text=True, env=dict(os.environ))
    if r.returncode:
        return None
    return json.loads(r.stdout)["Items"].get("telegram_token")


def chat_ids_for(job):
    """Allowed chats from the pack's vars file. A negative id is a group, and
    groups resolve command scopes before falling back to `default` — leaving
    all_group_chats empty is why the menu appeared in a DM but not in the
    shared media group."""
    path = "vars/" + job + ".hcl"
    if not os.path.exists(path):
        return []
    import re
    m = re.search(r'allowed_chat_ids\s*=\s*"([^"]*)"', open(path).read())
    if not m:
        return []
    return [c.strip() for c in m.group(1).split(",") if c.strip()]


def scopes_for(job):
    scopes = [ {"type": "default"},
               {"type": "all_private_chats"},
               {"type": "all_group_chats"} ]
    for cid in chat_ids_for(job):
        if cid.startswith("-"):
            scopes.append({"type": "chat", "chat_id": int(cid)})
    return scopes


def post(token, method, payload):
    req = urllib.request.Request(
        "https://api.telegram.org/bot" + token + "/" + method,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def main():
    failed = 0
    for job, cmds in COMMANDS.items():
        tok = token_for(job)
        if not tok:
            print("  %-14s no telegram_token in Nomad Variables" % job)
            failed += 1
            continue
        body = [{"command": c, "description": d} for c, d in cmds]
        done, bad = [], []
        for scope in scopes_for(job):
            try:
                if post(tok, "setMyCommands", {"commands": body, "scope": scope}).get("ok"):
                    done.append(scope["type"])
                else:
                    bad.append(scope["type"])
            except Exception as e:
                bad.append(scope["type"] + "(" + str(e)[:20] + ")")
        try:
            # The menu button is a private-chat affordance; in groups the "/"
            # list is the entry point.
            post(tok, "setChatMenuButton", {"menu_button": {"type": "commands"}})
        except Exception:
            pass
        print("  %-14s %d cmds -> %s%s" % (job, len(cmds), ",".join(done),
                                           ("  FAILED: " + ",".join(bad)) if bad else ""))
        failed += 1 if bad else 0
    return 1 if failed else 0


sys.exit(main())
