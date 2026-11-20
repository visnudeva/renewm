#!/usr/bin/env bash
# Install or update renewm (newm fork) for local testing.
# Safe beside another Wayland session (e.g. Swirl on SweetPotatOs).
#
# Usage:
#   ./install.sh              # deps + repywm + editable renewm + Ly session
#   ./install.sh --update     # git pull renewm (+ sibling repywm) + reinstall
#   ./install.sh --session    # launchers + Ly session desktop (no pip rebuild)
#   ./install.sh --no-session # skip Ly / wayland-sessions
set -euo pipefail

REPO_URL="${RENEWM_REPO_URL:-https://github.com/visnudeva/renewm.git}"
# Backend fork (still imports as Python package "pywm")
REPYWM_REPO_URL="${RENEWM_REPYWM_URL:-https://github.com/visnudeva/repywm.git}"
PYWM_URL="${RENEWM_PYWM_URL:-git+${REPYWM_REPO_URL}}"
SESSION_NAME="renewm"
SESSION_DIR_LY="/etc/ly/wayland-sessions"
SESSION_DIR_USER="${HOME}/.local/share/wayland-sessions"
LOCAL_BIN="${HOME}/.local/bin"
# Match SweetPotatOs: Ly's setup.sh exec's the desktop Exec= with a minimal PATH
# (no ~/.local/bin). Swirl uses /usr/local/bin/sweetpotatos-session — we do the same.
SYSTEM_BIN="/usr/local/bin"
SESSION_WRAPPER="${SYSTEM_BIN}/renewm-session"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Sibling checkout preferred for editable backend installs
REPYWM_DIR="${RENEWM_REPYWM_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)/repywm}"

DO_UPDATE=0
DO_SESSION=1
SESSION_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --update) DO_UPDATE=1 ;;
    --session) SESSION_ONLY=1 ;;
    --no-session) DO_SESSION=0 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

info() { printf '[*] %s\n' "$*"; }
ok()   { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

sudo_run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Need root for: $*" >&2
    exit 1
  fi
}

install_arch_deps() {
  if ! command -v pacman >/dev/null 2>&1; then
    warn "Not Arch/pacman — install build and runtime deps yourself (see README)."
    return 0
  fi
  info "Installing Arch packages…"
  # Keep this list to packages that exist in official repos. Pure-Python bits
  # that are AUR-only (pyfiglet, thefuzz, …) come from pip below — a missing
  # pacman target used to abort the whole script before building _pywm.so.
  local want=(
    python wayland libinput libxcb libxkbcommon mesa
    pixman xcb-util-errors xcb-util-renderutil xcb-util-wm seatd xorg-xwayland
    python-evdev python-numpy python-imageio python-cairo python-psutil
    python-pip python-setuptools python-wheel
    meson ninja wayland-protocols xorgproto git polkit
  )
  local optional=(python-pam python-dasbus alacritty)
  local pkgs=()
  local p
  for p in "${want[@]}" "${optional[@]}"; do
    if pacman -Si "$p" >/dev/null 2>&1 || pacman -Q "$p" >/dev/null 2>&1; then
      pkgs+=("$p")
    else
      warn "pacman package not found, skipping: $p"
    fi
  done
  if ((${#pkgs[@]})); then
    sudo_run pacman -S --needed --noconfirm "${pkgs[@]}"
  fi
  info "Installing Python deps via pip (pyfiglet, thefuzz, pam, dasbus, …)…"
  pip_user -q pyfiglet thefuzz python-pam dasbus pycairo psutil evdev imageio numpy || \
    pip_user pyfiglet thefuzz python-pam dasbus pycairo psutil
  ok "System + Python deps ready"
}

pip_user() {
  # Prefer pipx-free user installs; break-system-packages for Arch PEP 668 hosts.
  local pip=(python3 -m pip)
  if python3 -m pip install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
    pip+=(--break-system-packages)
  fi
  "${pip[@]}" install --user "$@"
}

ensure_path_hint() {
  mkdir -p "$LOCAL_BIN"
  if [[ ":$PATH:" != *":${LOCAL_BIN}:"* ]]; then
    warn "Add ${LOCAL_BIN} to PATH (e.g. fish: fish_add_path ${LOCAL_BIN})"
  fi
}

# Always install launchers from this checkout so Ly does not depend on pip
# copying hidden scripts (bin/.start-newm is easy to miss).
install_launchers() {
  info "Installing launchers into ${LOCAL_BIN} and ${SYSTEM_BIN}…"
  mkdir -p "$LOCAL_BIN"
  local f
  # Do not install hidden .start-newm — it breaks when _pywm is missing and
  # hides errors; start-newm runs Python directly.
  rm -f "${LOCAL_BIN}/.start-newm"
  for f in start-newm renewm-session newm-cmd newm-panel-basic; do
    if [[ -f "${SCRIPT_DIR}/bin/${f}" ]]; then
      install -Dm755 "${SCRIPT_DIR}/bin/${f}" "${LOCAL_BIN}/${f}"
    fi
  done
  # System wrapper for Ly (same pattern as sweetpotatos-session)
  if [[ -f "${SCRIPT_DIR}/bin/renewm-session" ]]; then
    info "Need sudo to install ${SESSION_WRAPPER}…"
    sudo_run install -Dm755 "${SCRIPT_DIR}/bin/renewm-session" "$SESSION_WRAPPER"
  fi
  if [[ ! -x "${LOCAL_BIN}/start-newm" ]]; then
    warn "start-newm missing after launcher install"
    return 1
  fi
  if [[ ! -x "$SESSION_WRAPPER" ]]; then
    warn "${SESSION_WRAPPER} missing — Ly will not be able to start renewm"
    return 1
  fi
  ok "Launchers: ${LOCAL_BIN}/start-newm , ${SESSION_WRAPPER}"
}

ensure_repywm_submodules() {
  local dir="$1"
  [[ -d "${dir}/.git" || -f "${dir}/.git" ]] || return 0
  if [[ -f "${dir}/.gitmodules" ]]; then
    info "Initializing repywm submodules (wlroots) in ${dir}…"
    git -C "$dir" submodule sync --recursive
    git -C "$dir" submodule update --init --recursive
  fi
  if [[ ! -f "${dir}/subprojects/wlroots/meson.build" ]]; then
    warn "wlroots submodule missing under ${dir}/subprojects/wlroots"
    warn "Run: git -C ${dir} submodule update --init --recursive"
    return 1
  fi
}

install_pywm() {
  if [[ -f "${REPYWM_DIR}/setup.py" ]] || [[ -f "${REPYWM_DIR}/pyproject.toml" ]]; then
    ensure_repywm_submodules "$REPYWM_DIR"
    info "Installing repywm (editable) from ${REPYWM_DIR}…"
    # Clean stale meson tree so a failed first build can recover
    rm -rf "${REPYWM_DIR}/build"
    info "Building native _pywm.so (this can take a few minutes)…"
    pip_user -e "${REPYWM_DIR}"
    if [[ ! -f "${REPYWM_DIR}/pywm/_pywm.so" ]]; then
      warn "pywm/_pywm.so missing after build — compositor will not start"
      return 1
    fi
    ok "repywm installed from local checkout"
  else
    info "No local repywm at ${REPYWM_DIR} — cloning ${REPYWM_REPO_URL}…"
    mkdir -p "$(dirname "$REPYWM_DIR")"
    git clone --recurse-submodules "$REPYWM_REPO_URL" "$REPYWM_DIR"
    ensure_repywm_submodules "$REPYWM_DIR"
    rm -rf "${REPYWM_DIR}/build"
    pip_user -e "${REPYWM_DIR}"
    ok "repywm/pywm installed from git checkout"
  fi
  python3 -c 'import pywm; print("pywm OK", pywm.__file__)' || {
    warn "pywm import failed after install"
    return 1
  }
}

install_renewm() {
  info "Installing renewm (editable) from ${SCRIPT_DIR}…"
  pip_user -e "${SCRIPT_DIR}"
  # Re-copy launchers: pip -e may overwrite start-newm with a weaker stub
  install_launchers
  python3 -c 'import newm, pywm; print("renewm+pywm OK")' || {
    warn "newm/pywm import check failed"
    return 1
  }
  ok "renewm package + launchers ready"
}

seed_config() {
  local dest="${HOME}/.config/newm/config.py"
  if [[ -f "$dest" ]]; then
    info "Config already exists: $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  local src="${SCRIPT_DIR}/newm/default_config.py"
  if [[ -f "$src" ]]; then
    cp -f "$src" "$dest"
    ok "Seeded ${dest} from default_config.py"
  else
    warn "No default_config.py found to seed"
  fi
}

session_exec_path() {
  # Absolute system path — Ly setup.sh does not include ~/.local/bin.
  echo "$SESSION_WRAPPER"
}

write_session_desktop() {
  local path="$1"
  local exec_cmd
  exec_cmd="$(session_exec_path)"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
[Desktop Entry]
Name=renewm
Comment=renewm (newm fork) — testing
Exec=${exec_cmd}
Type=Application
DesktopNames=newm;wlroots
EOF
}

install_session() {
  [[ "$DO_SESSION" -eq 1 ]] || return 0
  install_launchers

  info "Installing Wayland session entry…"
  info "SweetPotatOs Ly only reads ${SESSION_DIR_LY} (not ~/.local/share/wayland-sessions)"

  if [[ ! -x "$(session_exec_path)" ]]; then
    warn "Missing $(session_exec_path) — cannot register a working Ly session"
    return 1
  fi

  mkdir -p "$SESSION_DIR_USER"
  write_session_desktop "${SESSION_DIR_USER}/${SESSION_NAME}.desktop"
  ok "User copy: ${SESSION_DIR_USER}/${SESSION_NAME}.desktop"

  # Always try the Ly curated dir when /etc/ly exists (SPO sets waylandsessions there).
  if [[ -d /etc/ly ]] || [[ -d "$SESSION_DIR_LY" ]] || grep -qs 'waylandsessions.*/etc/ly' /etc/ly/config.ini 2>/dev/null; then
    info "Need sudo to install into ${SESSION_DIR_LY}…"
    sudo_run mkdir -p "$SESSION_DIR_LY"
    local tmp
    tmp="$(mktemp)"
    write_session_desktop "$tmp"
    sudo_run install -Dm644 "$tmp" "${SESSION_DIR_LY}/${SESSION_NAME}.desktop"
    rm -f "$tmp"
    if [[ -f "${SESSION_DIR_LY}/${SESSION_NAME}.desktop" ]]; then
      ok "Ly session: ${SESSION_DIR_LY}/${SESSION_NAME}.desktop"
      info "Exec=$(grep '^Exec=' "${SESSION_DIR_LY}/${SESSION_NAME}.desktop")"
      info "Sessions Ly will show:"
      ls -1 "$SESSION_DIR_LY" || true
    else
      warn "Failed to write ${SESSION_DIR_LY}/${SESSION_NAME}.desktop — renewm will not appear in Ly"
      return 1
    fi
  else
    warn "Ly not detected — only installed under ~/.local/share/wayland-sessions"
    warn "If you use Ly later, re-run: ./install.sh --session"
  fi
}

maybe_pull() {
  [[ "$DO_UPDATE" -eq 1 ]] || return 0
  if [[ -d "${SCRIPT_DIR}/.git" ]]; then
    info "git pull in ${SCRIPT_DIR}…"
    git -C "$SCRIPT_DIR" pull --ff-only
  else
    warn "Not a git checkout; skip pull. Clone from ${REPO_URL}"
  fi
  if [[ -d "${REPYWM_DIR}/.git" ]]; then
    info "git pull in ${REPYWM_DIR}…"
    git -C "$REPYWM_DIR" pull --ff-only
    ensure_repywm_submodules "$REPYWM_DIR" || true
  fi
}

main() {
  need_cmd python3
  need_cmd git

  if [[ "$SESSION_ONLY" -eq 1 ]]; then
    ensure_path_hint
    install_session
    exit 0
  fi

  maybe_pull
  install_arch_deps
  ensure_path_hint
  install_launchers
  install_pywm
  install_renewm
  seed_config
  install_session || warn "Session install failed — fix sudo, then: ./install.sh --session"

  echo
  ok "Done."
  echo "  Check launcher:   ls -l ~/.local/bin/start-newm ~/.local/bin/renewm-session"
  echo "  Start from a TTY: start-newm -d"
  echo "  Or pick 'renewm' at Ly (Exec= ~/.local/bin/renewm-session)."
  echo "  Confirm Ly file:  ls /etc/ly/wayland-sessions && cat /etc/ly/wayland-sessions/renewm.desktop"
  echo "  Log: ~/.cache/newm_log"
  echo "  Update later:     ./install.sh --update"
}

main
