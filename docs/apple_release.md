# Robots Beta on Apple platforms

Status 2026-09-28: the macOS app builds and runs from the committed export
preset. Signing and uploading need Apple's tools on a Mac with your Apple
developer account; nothing in the cloud sandbox can do that part.

## What is already set up
- Export preset **"Robots Beta (macOS)"** (`export_presets.cfg`): universal
  binary (Intel + Apple Silicon), bundle ID `com.thesdr.robotsbeta`, version
  0.1.0 (build 1), category Games, App Sandbox on, no other permissions.
- App name "Robots Beta" on macOS and iOS via a feature-tag override in
  `project.godot` (the editor and Windows builds keep the old name, so saves
  and playtest logs stay where they were).
- App icon `icon_app.png` (1024 px placeholder, replace any time).
- Texture format ETC2/ASTC enabled (Apple Silicon needs it). Your editor
  re-imports all textures once after pulling: expect a few minutes.
- God mode (F7) works only in debug/editor builds. F2/F3/F4 stay on so
  testers can send coordinates and perf logs.
- Verified in the cloud: export has no errors; the app bundle is a universal
  Mach-O named "Robots Beta"; the packed game boots to the menu and loads the
  full world headlessly. **Not verified: running on a real Mac.**

## Read this first: "Beta" and the App Store
Apple's App Review Guideline 2.2 says demos, betas and trials don't belong on
the App Store; betas go through **TestFlight**. So:
- **Robots Beta → TestFlight** (Mac TestFlight exists; up to 10,000 external
  testers by email or public link, after a light Beta App Review).
- A public App Store release later should drop "Beta" from the name and be a
  complete game (Guideline 4.2, minimum functionality).

## What you need
1. A Mac with Xcode installed (signing and the upload tool are Mac-only).
2. A paid Apple Developer Program membership.
3. Godot 4.7.2 on that Mac, with export templates (Editor > Manage Export Templates).

## Steps (on the Mac)
1. Pull the branch and open the project in Godot; let it finish importing.
2. **App Store Connect** > Apps > "+" > New App: platform macOS, name
   "Robots Beta", bundle ID `com.thesdr.robotsbeta` (register it first under
   Certificates, Identifiers & Profiles > Identifiers if it isn't listed).
   Change the ID in the preset if you want a different one; it must match.
3. **Certificates**: Xcode > Settings > Accounts > your team > Manage
   Certificates > add **Apple Distribution** and **Mac Installer Distribution**.
4. **Provisioning profile**: developer.apple.com > Profiles > "+" > Mac App
   Store Connect, for the bundle ID; download the `.provisionprofile`.
5. In Godot: Project > Export > "Robots Beta (macOS)":
   - Export > Distribution Type: **App Store**
   - Codesign > Codesign: **Xcode codesign**; Apple Team ID: your team ID;
     Identity: "Apple Distribution: …"; Installer Identity: "3rd Party Mac
     Developer Installer: …" (Mac Installer Distribution); Provisioning Profile:
     the file from step 4.
   - Export Project > save as **`Robots Beta.pkg`**.
6. Upload the `.pkg` with Apple's **Transporter** app (free, Mac App Store).
7. In App Store Connect > TestFlight: answer export compliance (the game uses
   no encryption), add testers. External testers trigger a short Beta App
   Review; it needs a description, a contact email and a privacy policy URL
   (the game collects no data; a one-paragraph page is enough).
8. Each new upload needs a higher build number: bump `application/version`
   (the "1") in the preset.

## Handing a test build to a friend without Apple (quick and dirty)
Export with the preset as it is committed (ad-hoc signed `.zip`), send the
zip. On their Mac: unzip, try to open, then System Settings > Privacy &
Security > "Open Anyway". Fine for a few friends, not for strangers.

## iPhone / iPad
Not done: the game needs a keyboard and mouse. An iOS build needs on-screen
touch controls (move stick, look drag, buttons for E, Tab, Q, click) and the
HUD sized for phones; that is its own piece of work. Godot's iOS export then
produces an Xcode project that is signed and uploaded from Xcode the same way.
