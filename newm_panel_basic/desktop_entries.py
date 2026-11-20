"""Discover applications from .desktop files for the renewm launcher."""
from __future__ import annotations

import os
from pathlib import Path


def _desktop_dirs() -> list[Path]:
    home = Path(os.environ.get("HOME", "/"))
    dirs = [
        home / ".local/share/applications",
        Path("/usr/local/share/applications"),
        Path("/usr/share/applications"),
    ]
    xdg = os.environ.get("XDG_DATA_DIRS", "")
    for part in xdg.split(":"):
        if part:
            dirs.append(Path(part) / "applications")
    # preserve order, drop missing / dupes
    seen: set[str] = set()
    out: list[Path] = []
    for d in dirs:
        key = str(d.resolve()) if d.exists() else str(d)
        if key in seen:
            continue
        seen.add(key)
        if d.is_dir():
            out.append(d)
    return out


def _parse_desktop(path: Path) -> tuple[str, str] | None:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    name = ""
    generic = ""
    exec_line = ""
    no_display = False
    hidden = False
    try_exec = ""
    terminal = False
    in_desktop_entry = False

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_desktop_entry = line == "[Desktop Entry]"
            continue
        if not in_desktop_entry:
            continue
        if line.startswith("Name=") and not name:
            name = line.split("=", 1)[1].strip()
        elif line.startswith("Name[") and not name:
            # Prefer first localized name only as fallback later
            if "en" in line.split("[", 1)[1].split("]", 1)[0]:
                name = line.split("=", 1)[1].strip()
        elif line.startswith("GenericName=") and not generic:
            generic = line.split("=", 1)[1].strip()
        elif line.startswith("Exec="):
            exec_line = line.split("=", 1)[1].strip()
        elif line.startswith("TryExec="):
            try_exec = line.split("=", 1)[1].strip()
        elif line.startswith("NoDisplay="):
            no_display = line.split("=", 1)[1].strip().lower() in ("1", "true", "yes")
        elif line.startswith("Hidden="):
            hidden = line.split("=", 1)[1].strip().lower() in ("1", "true", "yes")
        elif line.startswith("Terminal="):
            terminal = line.split("=", 1)[1].strip().lower() in ("1", "true", "yes")
        elif line.startswith("Type=") and line.split("=", 1)[1].strip() != "Application":
            return None

    if no_display or hidden or not exec_line:
        return None
    _ = try_exec  # soft: many .desktop files list TryExec we do not require

    # Strip desktop Exec field codes (%f %u %c …)
    parts: list[str] = []
    for tok in exec_line.split():
        if tok.startswith("%"):
            continue
        parts.append(tok)
    if not parts:
        return None
    cmd = " ".join(parts)
    if terminal:
        term = next(
            (
                t
                for t in ("foot", "alacritty", "kitty")
                if any(Path(p).joinpath(t).is_file() for p in os.environ.get("PATH", "").split(":"))
            ),
            "foot",
        )
        cmd = f"{term} -e {cmd}"

    title = name or generic or path.stem
    return title, cmd


def discover_entries() -> dict[str, str]:
    """Return title → command for launchable desktop apps."""
    entries: dict[str, str] = {}
    for d in _desktop_dirs():
        for path in sorted(d.glob("*.desktop")):
            parsed = _parse_desktop(path)
            if not parsed:
                continue
            title, cmd = parsed
            # First wins (user ~/.local before /usr)
            if title not in entries:
                entries[title] = cmd
    return entries


def default_shortcuts(entries: dict[str, str]) -> dict[int, tuple[str, str]]:
    """Number keys 1–9 for a few favourites if present."""
    prefer = [
        "foot",
        "Alacritty",
        "Firefox",
        "Firefox ESR",
        "Brave",
        "Chromium",
        "Kitty",
        "Files",
        "Nautilus",
        "Thunar",
        "SweetPotatOs Settings",
        "Settings",
    ]
    # case-insensitive match on keys
    lower_map = {k.lower(): (k, v) for k, v in entries.items()}
    shortcuts: dict[int, tuple[str, str]] = {}
    n = 1
    for want in prefer:
        hit = lower_map.get(want.lower())
        if not hit:
            # substring
            for k, pair in lower_map.items():
                if want.lower() in k:
                    hit = pair
                    break
        if hit and n <= 9:
            shortcuts[n] = hit
            n += 1
    return shortcuts
