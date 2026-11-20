#!/usr/bin/env bash
# Install or update renewm (newm fork) for local testing.
# Safe beside another Wayland session (e.g. Swirl on SweetPotatOs).
#
# Usage:
#   ./install.sh              # deps + pywm + editable renewm + Ly session
#   ./install.sh --update     # git pull (if in a clone) + reinstall packages
#   ./install.sh --session    # only (re)install the login-session desktop file
#   ./install.sh --no-session # skip Ly / wayland-sessions
set -euo pipefail

REPO_URL="${RENEWM_REPO_URL:-https://github.com/visnudeva/renewm.git}"
PYWM_URL="${RENEWM_PYWM_URL:-git+https://github.com/jbuchermn/pywm}"
SESSION_NAME="renewm"
SESSION_DIR_LY="/etc/ly/wayland-sessions"
SESSION_DIR_USER="${HOME}/.local/share/wayland-sessions"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  local pkgs=(
    python wayland libinput libxcb libxkbcommon mesa
    pixman xcb-util-errors xcb-util-renderutil xcb-util-wm seatd xorg-xwayland
    python-evdev python-numpy python-imageio python-cairo python-psutil
    python-pam python-pyfiglet python-thefuzz python-dasbus
    meson ninja wayland-protocols xorgproto git polkit
    python-pip python-setuptools python-wheel
  )
  # Optional but useful defaults
  command -v alacritty >/dev/null 2>&1 || pkgs+=(alacritty)
  sudo_run pacman -S --needed --noconfirm "${pkgs[@]}"
  ok "Arch packages ready"
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
  local bin="${HOME}/.local/bin"
  mkdir -p "$bin"
  if [[ ":$PATH:" != *":${bin}:"* ]]; then
    warn "Add ${bin} to PATH (e.g. fish: fish_add_path ${bin})"
  fi
}

install_pywm() {
  info "Installing pywm…"
  pip_user "$PYWM_URL"
  ok "pywm installed"
}

install_renewm() {
  info "Installing renewm (editable) from ${SCRIPT_DIR}…"
  pip_user -e "${SCRIPT_DIR}"
  ok "renewm installed (start-newm / newm-cmd on PATH after ~/.local/bin)"
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

write_session_desktop() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'EOF'
[Desktop Entry]
Name=renewm
Comment=renewm (newm fork) — testing
Exec=start-newm
Type=Application
DesktopNames=newm;wlroots
EOF
}

install_session() {
  [[ "$DO_SESSION" -eq 1 ]] || return 0
  info "Installing Wayland session entry…"
  mkdir -p "$SESSION_DIR_USER"
  write_session_desktop "${SESSION_DIR_USER}/${SESSION_NAME}.desktop"
  ok "User session: ${SESSION_DIR_USER}/${SESSION_NAME}.desktop"

  if [[ -d /etc/ly ]] || [[ -d "$SESSION_DIR_LY" ]]; then
    sudo_run mkdir -p "$SESSION_DIR_LY"
    local tmp
    tmp="$(mktemp)"
    write_session_desktop "$tmp"
    sudo_run install -Dm644 "$tmp" "${SESSION_DIR_LY}/${SESSION_NAME}.desktop"
    rm -f "$tmp"
    ok "Ly session: ${SESSION_DIR_LY}/${SESSION_NAME}.desktop (pick renewm at login)"
  else
    warn "Ly not detected — only installed user session under ~/.local/share/wayland-sessions"
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
}

main() {
  need_cmd python3
  need_cmd git

  if [[ "$SESSION_ONLY" -eq 1 ]]; then
    install_session
    exit 0
  fi

  maybe_pull
  install_arch_deps
  ensure_path_hint
  install_pywm
  install_renewm
  seed_config
  install_session

  echo
  ok "Done."
  echo "  Start from a TTY:  start-newm -d"
  echo "  Or pick 'renewm' at the login screen (Ly)."
  echo "  Log: ~/.cache/newm_log"
  echo "  Update later:      ./install.sh --update"
}

main
