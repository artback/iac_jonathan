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
        try:
            ok = post(tok, "setMyCommands",
                      {"commands": [{"command": c, "description": d} for c, d in cmds]}).get("ok")
            post(tok, "setChatMenuButton", {"menu_button": {"type": "commands"}})
            print("  %-14s %s %d commands" % (job, "OK" if ok else "FAILED", len(cmds)))
            failed += 0 if ok else 1
        except Exception as e:
            print("  %-14s failed: %s" % (job, str(e)[:60]))
            failed += 1
    return 1 if failed else 0


sys.exit(main())
