
### Installation Instructions
Copy and paste the following into your terminal:
```
HAS_NVIDIA=0
FREEDESKTOP_VERSION="24.08"
if [[ -f /proc/driver/nvidia/version ]]; then
    HAS_NVIDIA=1
    NVIDIA_VERSION=$(cat /proc/driver/nvidia/version | grep "NVRM version" | grep -oE '[0-9]{3,4}\.[0-9]{1,4}[\.0-9]+\s' | sed 's/\./-/g' | sed 's/ //g')
fi

flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# https://github.com/flatpak/flatpak/issues/3094
flatpak install --user -y --noninteractive flathub \
    org.freedesktop.Platform//${FREEDESKTOP_VERSION} \
    org.freedesktop.Platform.Compat.i386/x86_64/${FREEDESKTOP_VERSION} \
    org.freedesktop.Platform.GL32.default/x86_64/${FREEDESKTOP_VERSION}

if [[ ${HAS_NVIDIA} -eq 1 ]]; then
    flatpak install --user -y --noninteractive flathub \
        org.freedesktop.Platform.GL.nvidia-${NVIDIA_VERSION}/x86_64 \
        org.freedesktop.Platform.GL32.nvidia-${NVIDIA_VERSION}/x86_64
fi

flatpak run org.flatpak.Builder --install --user --force-clean --install-deps-from=flathub build-dir com.tarkov.Tarkov.yml && flatpak run com.tarkov.Tarkov
```
