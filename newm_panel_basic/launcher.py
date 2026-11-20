from __future__ import annotations
from typing import Any

import curses
import importlib
import logging
import os
import pathlib
import sys

from pyfiglet import Figlet  # type: ignore
from thefuzz import process  # type: ignore

from .desktop_entries import default_shortcuts, discover_entries

logger = logging.getLogger(__name__)


def _load_user_launcher() -> tuple[dict[str, str], dict[int, tuple[str, str]]]:
    entries: dict[str, str] = {}
    shortcuts: dict[int, tuple[str, str]] = {}

    home = os.environ.get("HOME", "/")
    path = pathlib.Path(home) / ".config" / "newm" / "launcher.py"
    if not path.is_file():
        path = pathlib.Path("/etc") / "newm" / "launcher.py"
    if not path.is_file():
        return entries, shortcuts

    logger.info("Loading launcher config at %s", path)
    module = path.stem
    try:
        del sys.modules[module]
    except KeyError:
        pass
    sys.path.insert(0, str(path.parent))
    res = importlib.import_module(module).__dict__
    if "entries" in res:
        entries = dict(res["entries"])
    if "shortcuts" in res:
        shortcuts = dict(res["shortcuts"])
    return entries, shortcuts


def _launcher() -> None:
    entries, shortcuts = _load_user_launcher()

    # Keep the newm spirit: figlet + fuzzy typeahead. Auto-fill from .desktop
    # files when the user has not curated a list yet (or merges with it).
    discovered = discover_entries()
    if not entries:
        entries = discovered
        logger.info("Using %d discovered desktop entries", len(entries))
    else:
        # User list wins on title clash; still add unknown apps underneath.
        for title, cmd in discovered.items():
            entries.setdefault(title, cmd)

    if not shortcuts:
        shortcuts = default_shortcuts(entries)

    def list_suggestions(search: str) -> list[tuple[str, str]]:
        if search == "":
            return []
        result = process.extract(search, list(entries.keys()), limit=12)
        return [(k[0], entries[k[0]]) for k in result if k[1] > 40]

    def render(scr: Any, search: str) -> None:
        suggestions = list_suggestions(search)
        _, width = scr.getmaxyx()
        shortcut_line = "   ".join("%d %s" % (k, v[0]) for k, v in sorted(shortcuts.items()))
        texts = [
            "",
            Figlet(font="big", justify="center", width=width).renderText("renewm"),
            Figlet(font="digital", justify="center", width=width).renderText(shortcut_line[: max(width - 4, 8)]),
            "    > " + search,
        ] + [("    + " if i == 0 else "      ") + t[0] for i, t in enumerate(suggestions)]

        if not search and not suggestions:
            texts.append("")
            texts.append("    type to search apps  ·  1-9 shortcuts  ·  Esc closes")

        scr.erase()
        y = 0
        max_y, _ = scr.getmaxyx()
        for t in texts:
            for line in t.split("\n"):
                if y >= max_y - 1:
                    break
                try:
                    scr.addstr(y, 0, line[: width - 1])
                except curses.error:
                    pass
                y += 1
        scr.refresh()

    scr = curses.initscr()
    try:
        curses.cbreak()
        curses.noecho()
        scr.keypad(True)
        curses.curs_set(False)

        while True:
            search = ""
            while True:
                render(scr, search)
                ch = scr.getch()
                if ch == curses.ERR or ch == 410:
                    continue
                if ch == 27:  # Esc — dismiss search / leave idle
                    if search:
                        search = ""
                        continue
                    # stay in panel; overlay gesture/key closes it
                    continue
                if ch == curses.KEY_BACKSPACE or ch == 127:
                    search = search[:-1] if search else ""
                elif ch == 10:
                    break
                else:
                    try:
                        search += chr(ch)
                    except Exception:
                        logger.exception("enter")

                try:
                    _ = int(search)
                    break
                except ValueError:
                    pass

            try:
                cmd = shortcuts[int(search)][1]
                logger.debug("Executing shortcut %s", cmd)
                os.system("newm-cmd launcher %s > /dev/null" % cmd)
                continue
            except Exception:
                pass

            suggestions = list_suggestions(search)
            if suggestions:
                logger.debug("Executing %s", suggestions[0][1])
                os.system("newm-cmd launcher %s > /dev/null" % suggestions[0][1])

    finally:
        curses.curs_set(True)
        scr.keypad(False)
        curses.echo()
        curses.endwin()


def launcher() -> None:
    while True:
        try:
            _launcher()
        except Exception:
            logger.exception("launcher crashed; restarting")
