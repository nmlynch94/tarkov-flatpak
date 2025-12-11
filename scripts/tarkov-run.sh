#!/bin/bash
set -e

uri="$1"
TARKOV_LAUNCHER_URL="https://prod.escapefromtarkov.com/launcher/download"
export PROTONPATH="GE-Latest"
export WINEPREFIX="$XDG_DATA_HOME/prefix"

cd "$XDG_DATA_HOME"

tarkov_installer_name="tarkov-setup.exe"

tarkov_launcher_exe_path="$WINEPREFIX/drive_c/Battlestate Games/BsgLauncher/BsgLauncher.exe"

if [[ ! -f "$tarkov_launcher_exe_path" ]]; then
  echo "Tarkov launcher not installed. Installing..."
  # Install dotnet48 and launch
  # TODO mouse focus registry key
  # umu-run winetricks -q dotnet48 vcrun2022
  curl -o "$tarkov_installer_name" -L "$TARKOV_LAUNCHER_URL"

  #BE workaround
  if zenity --question \
      --title="Info" \
      --text="In the next step, install the game. If it says to update that, click it. Click update if applicable until no more updates are available, and then close the launcher. Click yes to continue, or click no to abort."; then
    echo "Continuing..."
  else
    exit 0
  fi
  umu-run "$tarkov_installer_name"
  rm "$tarkov_installer_name"
  mkdir -p "$WINEPREFIX/drive_c/Battlestate Games/BsgLauncher"
  mkdir -p "$WINEPREFIX/drive_c/Program Files (x86)/Common Files/BattlEye"
  echo "d3d9.shaderModel = 1" > "$WINEPREFIX/drive_c/Battlestate Games/BsgLauncher/dxvk.conf"
  echo "Launcher closed. Performing BE workaround..."
  cp "$WINEPREFIX/drive_c/Battlestate Games/Escape from Tarkov/BattlEye/BEService_x64.exe" "$WINEPREFIX/drive_c/Program Files (x86)/Common Files/BattlEye/BEService_x64.exe" || true
  SERVICE_KEY='HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\BEService'

  # REG_SZ
  umu-run reg add "$SERVICE_KEY" /v DisplayName /t REG_SZ /d "BattlEye Service" /f
  umu-run reg add "$SERVICE_KEY" /v ImagePath /t REG_SZ /d "C:\\Program Files (x86)\\Common Files\\BattlEye\\BEService_x64.exe" /f
  umu-run reg add "$SERVICE_KEY" /v ObjectName /t REG_SZ /d "LocalSystem" /f

  # REG_DWORD
  umu-run reg add "$SERVICE_KEY" /v ErrorControl /t REG_DWORD /d 1 /f
  umu-run reg add "$SERVICE_KEY" /v PreshutdownTimeout /t REG_DWORD /d 180000 /f
  umu-run reg add "$SERVICE_KEY" /v Start /t REG_DWORD /d 2 /f
  umu-run reg add "$SERVICE_KEY" /v Type /t REG_DWORD /d 16 /f
  umu-run reg add "$SERVICE_KEY" /v WOW64 /t REG_DWORD /d 1 /f
  # umu-run reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v UseTakeFocus /t REG_DWORD /s "N" /f
  umu-run "$tarkov_launcher_exe_path" --disable-software-rasterizer

  exit 0
else
  umu-run "$tarkov_launcher_exe_path" --disable-software-rasterizer

  exit 0
fi
