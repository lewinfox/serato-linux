# Serato DJ in Docker

Serato DJ Pro or Lite (Windows build) on Linux, in an Ubuntu 24.04 image with wine-staging 11.16.
Built from [../rkb](../rkb) (rekordbox in Docker): same container plumbing, without the
rekordbox-specific Wine patches.

**Working** (Serato DJ Lite 4.0.10, Intel UHD laptop): install, Serato account sign-in,
SoundCloud sign-in, loading and playing tracks. **Not tried yet:** the DDJ-400 or any
other controller, USB sticks, Serato DJ Pro.

Prior art: [Dowdow/seratux](https://github.com/Dowdow/seratux) installs Serato into a
host Wine 11 prefix and registers the sign-in link. It doesn't handle controllers or
USB yet. This repo does the same in Docker, plus the fixes below and rkb's device passthrough.

## Use

```sh
make install                     # interactive: image, host setup, Serato, link handler, launcher
make container                   # just (re)build the image
./run.sh --install ~/Downloads/"Serato DJ Lite 4.0.10.zip"   # install or update Serato (Pro or Lite)
./run.sh                         # launch (or "Serato DJ" in the app menu)
./run.sh --check                 # health check
./run.sh bash                    # shell in the container
```

The installer needs a (free) Serato account to download, from
<https://serato.com/dj/pro/downloads> or <https://serato.com/dj/lite/downloads>.
`.exe` or `.zip` both work.

Plug the controller in before `./run.sh`: Docker only sees devices present at start
(though `/dev/snd` is shared live). The Wine prefix lives in `data/prefix`; `~/Music`
appears in Serato as `C:\users\dj\Music`, and Serato keeps its library in `~/Music/_Serato_`
(logs in `~/Music/_Serato_/Logs`).

## Fixes needed to get this far

- **Loading a track crashed Serato (1): Wine's Media Foundation.** Serato calls
  `MFCreateWaveFormatExFromMFMediaType` without the optional size pointer; Windows
  accepts that, Wine writes through it. The image builds a patched `mfplat.dll`
  (`files/mfplat-null-size.patch`). Not fixed in upstream Wine as of October 2026.
- **Loading a track crashed Serato (2): Wine's C++ runtime.** Serato then crashed in
  Wine's `msvcp140.dll`, which is incomplete. The real one from Microsoft's
  installer doesn't help on its own: the installer won't replace Wine's copy, because
  Wine's reports a newer version. So the image extracts Microsoft's DLLs into
  `/opt/vcrun`, and the launcher copies them into the prefix and sets Wine to prefer
  them (`native,builtin`). It does this on install and at each launch if they're missing.
- **Sign-in links.** Sign-in (account and SoundCloud) finishes in the host browser,
  which hands back a `seratodjlite://` (Lite) or `seratodjpro://` (Pro) link.
  `serato-link-handler.sh` is the host's handler for both (`make links`); it passes
  the link into the container, where a second Serato hands it to the running one.
  Two things it works around:
  - Links over about 260 characters (SoundCloud's are ~510) fail with "access
    denied" through Wine's `start` command. So the handler runs the Serato exe with
    the link directly.
  - Firefox sends the same link twice at once, and two links passed in together are
    both lost. So the handler delivers one at a time and skips a repeat.
  It logs each link (without the login code) to `data/link-handler.log`.
- **Quitting left the container running.** Serato's crash reporter
  (`crashpad_handler.exe`) outlives it, so the launcher stops Wine when Serato exits.
- `dwrite.dll` (text drawing) is patched as in rkb: emoji / NULL-text fixes.

## What's carried over from rkb

- GPU (Mesa GL/Vulkan), X11, PipeWire/PulseAudio, raw ALSA, USB bus, ntsync.
- GStreamer plugins so Wine can decode MP3/AAC; Microsoft core fonts.
- `files/devmirror`: mirrors USB sticks (`/dev/sd*`, read-only) and DJ-controller
  `hidraw` nodes into the container as they come and go. Defaults to Pioneer/AlphaTheta
  vendors; set `HID_VENDORS="xxxx yyyy"` (USB vendor IDs) for others.
- `files/xdg-open` + FIFO in `run.sh`: links open in the host browser.

## Gotchas

- The Microsoft core fonts download from SourceForge during the image build. When
  SourceForge was down (October 2026), the build failed at that step; the image was
  built from a copy of the Dockerfile that copies the fonts out of the `rekordbox-wine`
  image instead. A normal `make container` works once SourceForge is back.
- Serato takes ~15 seconds to start (its log reports the main thread hanging for 13 s).
- Crash dumps land in `data/prefix/drive_c/users/dj/AppData/Local/Serato/SeratoDJ/Dumps/reports`
  after you answer Serato's crash dialog.

## Controllers (not tried yet)

Serato talks to controllers over USB audio + MIDI, which Wine maps to ALSA. The
DDJ-400 is supported by Serato DJ Lite (free) and Pro (paid) with no Windows driver,
which is the best case for Wine. Controllers that need a Windows-only ASIO driver won't work.

## Licence

The scripts and docs in this repo are MIT (see `LICENSE`). Nothing third-party is
included: the image build downloads wine-staging (LGPL), Microsoft's core fonts
(accepting their EULA) and Microsoft's Visual C++ runtime (accepting its licence);
Serato you download yourself. Don't publish a built image without checking those licences.
