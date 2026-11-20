# renewm

Fork of [newm](https://github.com/jbuchermn/newm) for local experimentation. Upstream is unmaintained; see also [newm-atha](https://sr.ht/~atha/newm-atha/).

**renewm** is a Wayland compositor aimed at laptops and touchpads: windows live on a large 2D wall of tiles, and you navigate / zoom that wall (three-finger pan, four-finger zoom, `Logo` overview, etc.) instead of only tiling inside the panel.

Backend: **[repywm](https://github.com/visnudeva/repywm)** (fork of [pywm](https://github.com/jbuchermn/pywm)). Layout stays in Python here; rendering/input seat work lives in that C + wlroots repo. Both are ours to update and bugfix.

## Is it light?

Mostly yes for a test session.

- **Python (renewm)** drives layout, gestures, config, and panels — idle RAM is higher than a pure C compositor (Swirl / Hyprland / Sway).
- **repywm** (C + wlroots) handles the hot path — not interpreted Python frame-by-frame.

Expect something heavier than Swirl at idle, but far lighter than an Electron desktop. Fine as a **second session** on a SweetPotatOs laptop; keep Swirl as daily driver.

## Develop here, test on the laptop

| Machine | Role |
| --- | --- |
| **Ryoku** | Edit `renewm` and/or `repywm`, commit, `git push` |
| **SweetPotatOs laptop** | Clone / pull both, run `./install.sh`, pick **renewm** at Ly |

```sh
# Ryoku — compositor and/or backend
cd ~/code/GITHUB/renewm   # and/or ../repywm
git add -A && git commit -m "…" && git push

# SweetPotatOs (clone both once, side by side)
mkdir -p ~/code/GITHUB && cd ~/code/GITHUB
git clone https://github.com/visnudeva/renewm.git
git clone https://github.com/visnudeva/repywm.git
cd renewm && ./install.sh --update
```

Then log out and select **renewm** (Swirl stays available).

## Install

On Arch / SweetPotatOs, from a checkout (with `repywm` next to it when you want editable backend installs):

```sh
mkdir -p ~/code/GITHUB && cd ~/code/GITHUB
git clone https://github.com/visnudeva/renewm.git
git clone https://github.com/visnudeva/repywm.git
cd renewm
chmod +x install.sh
./install.sh
```

What the script does:

1. Installs pacman deps (skipped on non-Arch)
2. `pip install --user -e` **repywm** from `../repywm` if present, else from GitHub
3. `pip install --user -e` this repo
4. Seeds `~/.config/newm/config.py` once from `newm/default_config.py`
5. Adds a **renewm** Wayland session under `~/.local/share/wayland-sessions` and, if Ly is present, `/etc/ly/wayland-sessions`

Options:

```sh
./install.sh --update      # git pull renewm + sibling repywm, then reinstall
./install.sh --session     # only refresh the .desktop session file
./install.sh --no-session  # packages only, no Ly entry
```

Ensure `~/.local/bin` is on `PATH` so `start-newm` resolves.

Manual / non-Arch path:

```sh
pip3 install --user -e ../repywm   # or: git+https://github.com/visnudeva/repywm
pip3 install --user -e .
```

Debug start (e.g. from another TTY):

```sh
start-newm -d
```

Log: `~/.cache/newm_log`.

## Configuration

Python config from `~/.config/newm/config.py` (or `/etc/newm/config.py`). Defaults and keys: [`newm/default_config.py`](newm/default_config.py), [`doc/config.md`](doc/config.md).

Reload with `Mod+C` / `newm-cmd config` (default bindings; see default config).

Callbacks (`on_startup`, keybindings, …) run on the compositor thread — do not block.

## Docs (from upstream)

- [Tips and tricks](doc/tips_and_tricks.md)
- [Environment setup](doc/env_wayland.md)
- [Systemd](doc/systemd.md)
- [Look and feel](doc/look_and_feel.md)
- [Arch notes](doc/install_Arch_Linux.md)

### newm-cmd

- `newm-cmd inhibit-idle` — stay awake
- `newm-cmd config` — reload config
- `newm-cmd lock` / `unlock` — lock screen
- `newm-cmd debug` — dump view state

## License

Same as upstream: see [LICENSE](LICENSE).
