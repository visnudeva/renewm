"""
renewm starter config tuned for SweetPotatOs (foot, French AZERTY-friendly binds,
polkit, simple top bar).

Install:
  mkdir -p ~/.config/newm
  cp examples/config.sweetpotatos.py ~/.config/newm/config.py
  # then Mod+C to reload, or log out/in
"""
from __future__ import annotations

import os
import pwd
import time
from pathlib import Path
from typing import Any, Callable

from newm.helper import BacklightManager, PaCtl, WobRunner
from newm.layout import Layout

HOME = Path.home()


def _wallpaper() -> str:
    candidates = [
        HOME / ".config/swirl/wallpaper.conf",  # may be an include, skip if not image
        HOME / "Pictures/wallpapers/SpoNeon.png",
        HOME / "code/GITHUB/SweetPotato/backgrounds/NewSpoNeonBG.png",
        HOME / "code/GITHUB/SweetPotato/backgrounds/SPONeonKanjiDefault.png",
        Path("/usr/share/backgrounds/sway/SpoNeon.png"),
        Path("/usr/share/backgrounds/SpoNeon.png"),
    ]
    for p in candidates:
        if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}:
            return str(p)
    # bundled fallback
    import newm

    return str(Path(newm.__file__).parent / "resources" / "wallpaper.jpg")


def _term() -> str:
    for cmd in ("foot", "alacritty", "kitty", "wezterm"):
        if any(Path(p).joinpath(cmd).is_file() for p in os.environ.get("PATH", "").split(":")):
            return cmd
    return "foot"


TERM = _term()

background = {
    "path": _wallpaper(),
    "anim": True,
    "time_scale": 0.15,
}

# Common laptop panel name; renewm places unknown outputs automatically.
outputs = [
    {"name": "eDP-1"},
]

corner_radius = 16
view = {
    "corner_radius": 10,
    "padding": 8,
}

focus = {
    "enabled": True,
    "color": "#E8A0BF88",  # soft SweetPotato-ish pink
    "distance": 3,
    "width": 2,
}

pywm = {
    "enable_xwayland": True,
    "xkb_layout": "fr",
    "xkb_options": "caps:escape",
    "tap_to_click": True,
    "natural_scroll": True,
    "focus_follows_mouse": True,
    "encourage_csd": False,
    "texture_shaders": "basic",
    "renderer_mode": "pywm",
}

# OSD bar for volume / brightness (optional package: wob)
wob_runner = WobRunner("wob -a bottom -M 100") if any(
    Path(p).joinpath("wob").is_file() for p in os.environ.get("PATH", "").split(":")
) else None
backlight_manager = BacklightManager(
    anim_time=0.5, bar_display=wob_runner
)


def synchronous_update() -> None:
    backlight_manager.update()


pactl = PaCtl(0, wob_runner)


def _run(cmd: str) -> None:
    os.system(f"{cmd} &")


def on_startup() -> None:
    # Environment for portals / Electron
    os.system(
        "systemctl --user import-environment "
        "DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null"
    )
    os.system(
        "dbus-update-activation-environment --systemd "
        "DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null"
    )
    for cmd in (
        "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
        "/usr/lib/polkit-kde-authentication-agent-1",
        "mako",
    ):
        # start once if binary exists
        name = Path(cmd).name
        if Path(cmd).is_file() or any(
            Path(p).joinpath(name).is_file() for p in os.environ.get("PATH", "").split(":")
        ):
            os.system(f"pgrep -x {name} >/dev/null || {cmd} &")


def on_reconfigure() -> None:
    os.system('notify-send renewm "Config reloaded" 2>/dev/null &')


def key_bindings(layout: Layout) -> list[tuple[str, Callable[[], Any]]]:
    return [
        # Navigate the wall
        ("L-h", lambda: layout.move(-1, 0)),
        ("L-j", lambda: layout.move(0, 1)),
        ("L-k", lambda: layout.move(0, -1)),
        ("L-l", lambda: layout.move(1, 0)),
        ("L-u", lambda: layout.basic_scale(1)),
        ("L-n", lambda: layout.basic_scale(-1)),
        ("L-t", lambda: layout.move_in_stack(1)),
        # Move / resize focused window
        ("L-H", lambda: layout.move_focused_view(-1, 0)),
        ("L-J", lambda: layout.move_focused_view(0, 1)),
        ("L-K", lambda: layout.move_focused_view(0, -1)),
        ("L-L", lambda: layout.move_focused_view(1, 0)),
        ("L-C-h", lambda: layout.resize_focused_view(-1, 0)),
        ("L-C-j", lambda: layout.resize_focused_view(0, 1)),
        ("L-C-k", lambda: layout.resize_focused_view(0, -1)),
        ("L-C-l", lambda: layout.resize_focused_view(1, 0)),
        # Apps
        ("L-Return", lambda: _run(TERM)),
        ("L-space", lambda: _run(f"{TERM} -e newm-panel-basic launcher")),
        ("L-q", lambda: layout.close_focused_view()),
        ("L-f", lambda: layout.toggle_fullscreen()),
        ("L-", lambda: layout.toggle_overview()),
        # Session
        ("L-C", lambda: layout.update_config()),
        ("L-p", lambda: layout.ensure_locked(dim=True)),
        ("L-P", lambda: layout.terminate()),
        # Hardware keys
        ("XF86MonBrightnessUp", lambda: backlight_manager.set(backlight_manager.get() + 0.08)),
        ("XF86MonBrightnessDown", lambda: backlight_manager.set(backlight_manager.get() - 0.08)),
        ("XF86AudioRaiseVolume", lambda: pactl.volume_adj(5)),
        ("XF86AudioLowerVolume", lambda: pactl.volume_adj(-5)),
        ("XF86AudioMute", lambda: pactl.mute()),
    ]


def _battery() -> str:
    bat = Path("/sys/class/power_supply/BAT0/capacity")
    if bat.is_file():
        try:
            return f"{bat.read_text().strip()}%"
        except OSError:
            pass
    return ""


panels = {
    "lock": {
        "cmd": f"{TERM} -e newm-panel-basic lock",
    },
    "launcher": {
        "cmd": f"{TERM} -e newm-panel-basic launcher",
    },
    "top_bar": {
        "native": {
            "enabled": True,
            "texts": lambda: [
                pwd.getpwuid(os.getuid())[0],
                _battery(),
                time.strftime("%a %d %b  %H:%M"),
            ],
        }
    },
    "bottom_bar": {
        "native": {
            "enabled": False,
            "texts": lambda: ["renewm"],
        }
    },
}

energy = {
    "idle_callback": backlight_manager.callback,
}
