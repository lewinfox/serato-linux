# Serato DJ (Pro or Lite) under wine-staging 11.16, with patched dwrite.dll and mfplat.dll
# and Microsoft's C++ runtime.
# Build:  make container      Run:  ./run.sh
# Based on github.com/lewinfox/rekordbox-linux's Dockerfile, minus its rekordbox-specific Wine patches.
FROM ubuntu:24.04

ARG WINE_PKG_VER=11.16~noble-1
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# WineHQ repo, wine-staging pinned so the dwrite patches below apply.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
    | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key \
 && curl -fsSL -o /etc/apt/sources.list.d/winehq-noble.sources \
    https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources \
 && apt-get update \
 && apt-get install -y --install-recommends \
    winehq-staging=$WINE_PKG_VER wine-staging=$WINE_PKG_VER \
    wine-staging-amd64=$WINE_PKG_VER wine-staging-i386:i386=$WINE_PKG_VER \
 && apt-mark hold winehq-staging wine-staging wine-staging-amd64 wine-staging-i386:i386 \
 && rm -rf /var/lib/apt/lists/*

# Build tools (for the dwrite patch below) plus runtime helpers.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git make gcc clang lld python3 flex bison binutils xz-utils patch file \
    devscripts debhelper \
    libx11-dev libxext-dev libxrandr-dev libxcomposite-dev libxfixes-dev \
    libxi-dev libxcursor-dev libxrender-dev libxinerama-dev \
    libasound2-dev libdbus-1-dev libfreetype-dev libgnutls28-dev \
    libusb-1.0-0-dev libudev-dev libfontconfig-dev \
    libgl-dev libegl-dev libvulkan-dev libxxf86vm-dev libxkbcommon-dev libxshmfence-dev \
    alsa-utils pipewire-alsa pulseaudio-utils usbutils kmod \
    fonts-noto-core fonts-liberation2 xdg-utils \
 && rm -rf /var/lib/apt/lists/*

# Wine's .NET (Mono) and browser (Gecko) add-ons, in the shared folder Wine checks
# first, so new prefixes don't prompt to download them. Versions must match Wine.
ARG MONO_VER=11.3.0
ARG GECKO_VER=2.47.4
RUN d=/opt/wine-staging/share/wine \
 && mkdir -p $d/mono $d/gecko \
 && curl -fsSL https://dl.winehq.org/wine/wine-mono/$MONO_VER/wine-mono-$MONO_VER-x86.tar.xz | tar -xJ -C $d/mono \
 && for a in x86 x86_64; do \
      curl -fsSL https://dl.winehq.org/wine/wine-gecko/$GECKO_VER/wine-gecko-$GECKO_VER-$a.tar.xz | tar -xJ -C $d/gecko; \
    done

# Mesa OpenGL/Vulkan drivers: wined3d (Direct3D) renders through these.
RUN apt-get update && apt-get install -y --no-install-recommends unzip mesa-utils vulkan-tools \
    libgl1 libglx-mesa0 libegl1 libegl-mesa0 libgl1-mesa-dri mesa-vulkan-drivers libvulkan1 \
    libgl1:i386 libglx-mesa0:i386 libegl1:i386 libegl-mesa0:i386 libgl1-mesa-dri:i386 mesa-vulkan-drivers:i386 libvulkan1:i386 && rm -rf /var/lib/apt/lists/*

# GStreamer decoders: Wine decodes MP3/AAC through these (plugins-base alone reads no MP3).
# icoutils: pulls the app icon out of the Serato exe for the desktop launcher.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools \
    icoutils \
 && rm -rf /var/lib/apt/lists/*

# Microsoft core fonts (real Arial, Verdana...), so Windows apps' text isn't set in a
# wider fallback and truncated. Installing means accepting Microsoft's core fonts EULA.
RUN echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections \
 && apt-get update && apt-get install -y --no-install-recommends ttf-mscorefonts-installer \
 && fc-list | grep -qi "Arial.ttf" \
 && rm -rf /var/lib/apt/lists/*

# Patched Wine DLLs, built from the matching Wine source (borrowing import
# libraries from the package) and installed over the stock ones:
#  - dwrite.dll (text drawing), from rekordbox-linux. Stock Wine reads a NULL pointer on
#    some strings (emoji in track names) and has no emoji fallback font. Symbola
#    supplies the emoji glyphs.
#  - mfplat.dll (Media Foundation). Serato crashes loading a track: it passes a
#    NULL size pointer that stock Wine writes through.
RUN apt-get update && apt-get install -y --no-install-recommends fonts-symbola \
 && fc-list | grep -qi "Symbola" \
 && rm -rf /var/lib/apt/lists/*
COPY files/dwrite-null-text.patch files/dwrite-emoji-fallback.patch files/mfplat-null-size.patch /tmp/
RUN v="${WINE_PKG_VER%%~*}" && pe=/opt/wine-staging/lib/wine/x86_64-windows \
 && mkdir /tmp/wb && cd /tmp/wb \
 && curl -fsSL "https://dl.winehq.org/wine/source/${v%%.*}.x/wine-$v.tar.xz" | tar -xJ \
 && cd "wine-$v" && for p in /tmp/dwrite-*.patch /tmp/mfplat-*.patch; do patch -p1 < "$p" || exit 1; done \
 && ./configure --enable-win64 --disable-tests >/dev/null \
 && make -j"$(nproc)" tools/winebuild/winebuild >/dev/null \
 && for t in $(grep -oE '^dlls/[^ :]+/x86_64-windows/lib[^ :]+\.a:' Makefile | tr -d ':' | sort -u); do \
      if [ -f "$pe/$(basename "$t")" ] && [ ! -e "$t" ]; then mkdir -p "$(dirname "$t")" && cp "$pe/$(basename "$t")" "$t"; fi; \
    done \
 && touch -d '+1 day' dlls/*/x86_64-windows/lib*.a \
 && make -j"$(nproc)" dlls/dwrite/x86_64-windows/dwrite.dll dlls/mfplat/x86_64-windows/mfplat.dll >/dev/null \
 && [ "$(strings -a dlls/dwrite/x86_64-windows/dwrite.dll | grep -c RBW-DWRITE)" -gt 0 ] \
 && [ "$(strings -a -el dlls/dwrite/x86_64-windows/dwrite.dll | grep -c Symbola)" -gt 0 ] \
 && [ "$(strings -a dlls/mfplat/x86_64-windows/mfplat.dll | grep -c SERATO-MFPLAT)" -gt 0 ] \
 && install -m644 dlls/dwrite/x86_64-windows/dwrite.dll "$pe/dwrite.dll" \
 && install -m644 dlls/mfplat/x86_64-windows/mfplat.dll "$pe/mfplat.dll" \
 && cd / && rm -rf /tmp/wb /tmp/dwrite-*.patch /tmp/mfplat-*.patch

# Microsoft's C++ runtime (msvcp140 etc.), extracted from Microsoft's installer.
# Wine's own msvcp140 is incomplete and Serato crashes in it loading a track.
# The installer won't replace Wine's copy (it reports a newer version), so
# serato-wine copies these into the prefix and tells Wine to prefer them.
# Using them means accepting Microsoft's Visual C++ runtime licence.
RUN apt-get update && apt-get install -y --no-install-recommends cabextract \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /opt/vcrun /tmp/vc && cd /tmp/vc \
 && curl -fsSL -o vc_redist.x64.exe https://aka.ms/vs/17/release/vc_redist.x64.exe \
 && cabextract -q -F 'a1*' vc_redist.x64.exe \
 && for c in a1*; do cabextract -q -L -d out "$c" 2>/dev/null || true; done \
 && for d in msvcp140 msvcp140_1 msvcp140_2 msvcp140_atomic_wait msvcp140_codecvt_ids concrt140; do \
      install -m644 "out/$d.dll_amd64" "/opt/vcrun/$d.dll" || exit 1; \
    done \
 && cd / && rm -rf /tmp/vc

# Non-root user matching the host uid, in the host's audio group (gid 29).
RUN (userdel -r ubuntu 2>/dev/null || true) \
 && groupadd -g $GID dj && useradd -m -u $UID -g $GID -G audio -s /bin/bash dj
RUN install -d -o dj -g dj -m 700 /run/user/$UID
COPY files/xdg-open /usr/local/bin/xdg-open
COPY files/devmirror /usr/local/bin/devmirror
COPY files/serato-wine /usr/local/bin/serato-wine
USER dj
WORKDIR /home/dj
ENV WINEPREFIX=/home/dj/prefix WINEDEBUG=-all XDG_RUNTIME_DIR=/run/user/1000

CMD ["serato-wine"]
