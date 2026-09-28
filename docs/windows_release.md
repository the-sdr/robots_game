# Robots Beta for Windows

One self-contained file: `Robots Beta.exe` (about 480 MB, game data embedded).
64-bit Windows, no installer, no other files needed.

## Make the exe (on your laptop, about a minute)
1. Pull the branch and open the project in Godot 4.7.2; let it finish importing.
2. Editor > Manage Export Templates > Download and Install (once per machine).
3. Project > Export > **Robots Beta (Windows)** > Export Project. Untick
   "Export With Debug" for the release build. It writes `build/windows/Robots Beta.exe`.

## Hand it to testers
- Share the exe through a cloud drive link (too big for email).
- Windows SmartScreen will warn that the publisher is unknown, because the exe
  isn't code-signed: testers click **More info > Run anyway**. Signing needs a
  paid code-signing certificate; not worth it for a beta.
- Saves and F3/F4 logs go to `%APPDATA%\Godot\app_userdata\Robots Beta\`
  (`save.json`, `playtest\saves.md`, `playtest\perf.md`). Ask testers to send
  `perf.md` along with notes.
- Needs a graphics driver with Vulkan (any Intel UHD, AMD or NVIDIA from the
  last ~8 years with current drivers).

## What's in it
Version 0.1.0 (file version 0.1.0.1), product name "Robots Beta", robot-head
icon, window title "Robots Beta". God mode (F7) is off; F2/F3/F4 stay on.
The editor keeps its own name and save folder, so your playtests are unaffected.

## Verified in the cloud (2026-09-28)
Export has no errors; the file is a 64-bit Windows GUI executable with the
version info and icon; its embedded game data boots to the menu and loads the
whole world (forest, all tree models, the Hub) headlessly, with the tools and
design folders left out. **Not verified: running on Windows** (no Windows or
GPU in the sandbox).
