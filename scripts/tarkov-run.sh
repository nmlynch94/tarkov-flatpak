#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'

# -----------------------------
# Logging + error handling
# -----------------------------
ts() { date +"%Y-%m-%d %H:%M:%S"; }
log_info()  { echo "[$(ts)] [INFO]  $*"; }
log_warn()  { echo "[$(ts)] [WARN]  $*" >&2; }
log_error() { echo "[$(ts)] [ERROR] $*" >&2; }
die()       { log_error "$*"; exit 1; }

on_err() {
  local exit_code=$?
  log_error "Command failed (exit=$exit_code) at ${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${BASH_COMMAND}"
  exit "$exit_code"
}
trap on_err ERR

run() {
  log_info ">> $*"
  "$@"
}

# -----------------------------
# Config
# -----------------------------
TARKOV_LAUNCHER_URL="https://prod.escapefromtarkov.com/launcher/download"

export PROTONPATH="${PROTONPATH:-GE-Latest}"
export WINEPREFIX="${WINEPREFIX:-$XDG_DATA_HOME/prefix}"
export WINEDEBUG="-all"

cd "${XDG_DATA_HOME:?XDG_DATA_HOME is not set}"

STATE_DIR="$XDG_DATA_HOME/.tarkov-state"
mkdir -p "$STATE_DIR"

tarkov_installer_name="tarkov-setup.exe"
tarkov_launcher_exe_path="$WINEPREFIX/drive_c/Battlestate Games/BsgLauncher/BsgLauncher.exe"
spt_dir="$WINEPREFIX/drive_c/SPT/SPT"

SERVICE_KEY='HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\BEService'

# -----------------------------
# Helpers
# -----------------------------
have_file() { [[ -f "$1" ]]; }
mark_done() { : > "$STATE_DIR/$1.done"; }
is_done()   { [[ -f "$STATE_DIR/$1.done" ]]; }

download() {
  local url="$1"
  local dest="$2"

  if [[ -s "$dest" ]]; then
    log_info "Already downloaded: $dest"
    return 0
  fi

  log_info "Downloading: $url -> $dest"
  run curl -fL --retry 3 --retry-delay 1 --connect-timeout 10 -o "$dest" "$url"
}

# Cache winetricks installed list once per run
WINETRICKS_INSTALLED_LIST=""
winetricks_refresh_installed() {
  WINETRICKS_INSTALLED_LIST="$(PROTONPATH="UMU-Latest" umu-run winetricks list-installed 2>/dev/null | awk '{print $1}' || true)"
}
winetricks_has() {
  local verb="$1"
  [[ -n "${WINETRICKS_INSTALLED_CACHE:-}" ]] || winetricks_refresh_installed
  grep -qx "$verb" <<<"${WINETRICKS_INSTALLED_CACHE-}"
}
winetricks_ensure() {
  # Usage: winetricks_ensure verb1 verb2 ...
  local verbs=("$@")
  local to_install=()

  for v in "${verbs[@]}"; do
    if winetricks_has "$v"; then
      log_info "winetricks already installed: $v"
    else
      to_install+=("$v")
    fi
  done

  if ((${#to_install[@]} == 0)); then
    return 0
  fi

  log_info "Installing winetricks verbs: ${to_install[*]}"
  # Use UMU-Latest for some verbs not working with proton 10+
  PROTONPATH="UMU-Latest" run umu-run winetricks -q "${to_install[@]}"
  winetricks_refresh_installed
}

zenity_confirm_or_exit() {
  local title="$1"
  local text="$2"
  if zenity --question --title="$title" --text="$text"; then
    return 0
  fi
  log_warn "User aborted."
  exit 0
}

ensure_be_workaround() {
  local src="$WINEPREFIX/drive_c/Battlestate Games/Escape from Tarkov/BattlEye/BEService_x64.exe"
  local dst_dir="$WINEPREFIX/drive_c/Program Files (x86)/Common Files/BattlEye"
  local dst="$dst_dir/BEService_x64.exe"

  mkdir -p "$dst_dir"

  if have_file "$dst"; then
    log_info "BattlEye service binary already present: $dst"
  else
    have_file "$src" || die "Expected BattlEye service binary missing: $src (is EFT installed yet?)"
    log_info "Copying BattlEye service binary -> Common Files"
    run cp "$src" "$dst"
  fi

  log_info "Ensuring BattlEye service registry keys"
  run umu-run reg add "$SERVICE_KEY" /v DisplayName /t REG_SZ /d "BattlEye Service" /f
  run umu-run reg add "$SERVICE_KEY" /v ImagePath   /t REG_SZ /d "C:\\Program Files (x86)\\Common Files\\BattlEye\\BEService_x64.exe" /f
  run umu-run reg add "$SERVICE_KEY" /v ObjectName  /t REG_SZ /d "LocalSystem" /f

  run umu-run reg add "$SERVICE_KEY" /v ErrorControl       /t REG_DWORD /d 1      /f
  run umu-run reg add "$SERVICE_KEY" /v PreshutdownTimeout /t REG_DWORD /d 180000 /f
  run umu-run reg add "$SERVICE_KEY" /v Start              /t REG_DWORD /d 2      /f
  run umu-run reg add "$SERVICE_KEY" /v Type               /t REG_DWORD /d 16     /f
  run umu-run reg add "$SERVICE_KEY" /v WOW64              /t REG_DWORD /d 1      /f
}

ensure_dxvk_conf() {
  local conf="$WINEPREFIX/drive_c/Battlestate Games/BsgLauncher/dxvk.conf"
  if [[ -f "$conf" ]] && grep -q '^d3d9\.shaderModel = 1$' "$conf"; then
    log_info "dxvk.conf already configured"
  else
    log_info "Writing dxvk.conf"
    mkdir -p "$(dirname "$conf")"
    echo "d3d9.shaderModel = 1" > "$conf"
  fi
}

ensure_dotnet9_runtimes() {
  if is_done "dotnet9_runtimes"; then
    log_info ".NET 9 runtimes already installed (marker present)"
    return 0
  fi

  download "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/9.0.11/windowsdesktop-runtime-9.0.11-win-x64.exe" "$XDG_DATA_HOME/dotnet-runtime.exe"
  download "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/9.0.11/aspnetcore-runtime-9.0.11-win-x64.exe" "$XDG_DATA_HOME/aspnet-core.exe"

  run umu-run "$XDG_DATA_HOME/dotnet-runtime.exe" /q || log_warn "dotnet-runtime installer returned non-zero (continuing)"
  run umu-run "$XDG_DATA_HOME/aspnet-core.exe" /q  || log_warn "aspnet-core installer returned non-zero (continuing)"

  mark_done "dotnet9_runtimes"
}

ensure_spt_installer() {
  if is_done "spt_installed"; then
    log_info "SPT installer step already completed (marker present)"
    return 0
  fi

  mkdir -p "$WINEPREFIX/drive_c/SPT"

  winetricks_ensure arial times dotnetdesktop6 dotnetdesktop8 dotnetdesktop9

  download "https://ligma.waffle-lord.net/SPTInstaller.exe" "$XDG_DATA_HOME/SPTInstaller.exe"
  run umu-run "$XDG_DATA_HOME/SPTInstaller.exe" installpath="C:\SPT"

  # Ensure Linux server bit is executable
  if have_file "$spt_dir/SPT.Server.Linux"; then
    run chmod +x "$spt_dir/SPT.Server.Linux"
  else
    log_warn "Expected SPT.Server.Linux not found at: $spt_dir/SPT.Server.Linux (installer may have changed layout)"
  fi

  run umu-run winecfg /v win81

  mark_done "spt_installed"
}

# -----------------------------
# Main flow
# -----------------------------
log_info "Starting. PROTONPATH=$PROTONPATH WINEPREFIX=$WINEPREFIX"

if [[ ! -d "$spt_dir" ]]; then
  log_info "SPT not detected. Running first-time setup…"

  # Core deps for launcher (idempotent via list-installed)
  # Note: you previously forced UMU-Latest specifically for dotnet48; keep that behavior.
  winetricks_ensure dotnet48 vcrun2022

  # Install EFT launcher if missing
  if have_file "$tarkov_launcher_exe_path"; then
    log_info "Tarkov launcher already present: $tarkov_launcher_exe_path"
  else
    download "$TARKOV_LAUNCHER_URL" "$XDG_DATA_HOME/$tarkov_installer_name"

    zenity_confirm_or_exit "Info" \
"In the next step, install the game.
If it says to update after it completes, update.
Click update until no more updates are available, then close the launcher.
UNCHECK “Launch after install”.
Click Yes to continue, or No to abort."

    run umu-run "$XDG_DATA_HOME/$tarkov_installer_name"
    run rm -f "$XDG_DATA_HOME/$tarkov_installer_name"
  fi

  # Launch once to let it self-update (safe to do repeatedly)
  if have_file "$tarkov_launcher_exe_path"; then
    run umu-run "$tarkov_launcher_exe_path" --disable-software-rasterizer
  else
    die "Launcher EXE still not found after install attempt: $tarkov_launcher_exe_path"
  fi

  ensure_dxvk_conf
  ensure_be_workaround
  ensure_dotnet9_runtimes
  ensure_spt_installer

  log_info "First-time setup complete."
  exit 0
fi

# Already installed path
log_info "SPT detected. Starting server + launcher…"
cd "$spt_dir"

run "./SPT.Server.Linux" &
run env WINEDLLOVERRIDES="winhttp=n,b" umu-run "SPT.Launcher.exe"
