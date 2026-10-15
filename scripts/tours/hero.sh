# shellcheck shell=bash
# StartDrive's tour: the animation at the top of the README (screenshots/hero.avif).
# Run it with scripts/tour.sh scripts/tours/hero.sh --install (or scripts/hero.sh --install).
#
# The story: every drive in one window, with what is uploading and how much room is left; a switch to
# mount one as a folder; per-drive settings that apply at once; the keyboard; the app's own settings (the
# bar icon among them); and a window that opens where it was left.
#
# It runs in a sandbox on the demo drives of lib/demo.sh (nothing real: no mounts, no accounts, no files of
# yours), so the same drives are in every recording and nothing can be changed by a click that goes astray.
# In the sandbox it changes: the saved size and place of both windows (reset to the defaults), a mount, a
# cache setting and the read-only flag of the demo drives, and the bar icon.

TOUR_TITLE=StartDrive
TOUR_OUT=screenshots/hero.avif
TOUR_LAYER=omarchy-startdrive
TOUR_STEPS=7

# This plugin runs in the sandbox on fixture drives: nothing of the real config is copied in.
TOUR_PLUGIN_ID=io.github.bmaltais.startdrive
TOUR_SANDBOX_COPY=()
TOUR_SANDBOX_LINK=(.local/share/icons)
# The recorder proves the tour touched none of these (it fails the run if one changed). It lists them recursively, so never
# name ~/Cloud or anything else a mount lives under: walking a live cloud mount is slow and spends the drive's API quota.
TOUR_REAL_UNCHANGED=(.config/omarchy/shell.json .config/startdrive .config/systemd/user .config/rclone .local/share/applications/startdrive.desktop .local/bin/startdrive)

ID=io.github.bmaltais.startdrive
# Worked out when used, so that (HOME being the sandbox) it is the sandbox's.
demo_dir() { echo "$HOME/.config/startdrive/demo"; }

tour_prepare() {
  # Both windows start where the defaults put them.
  "$REPO/bin/startdrive" window --reset >/dev/null
  "$REPO/bin/startdrive" window --reset-setup >/dev/null
}

tour_play() {
  # 1. Every drive in one window.
  cap "All your cloud drives in one window"
  omarchy-shell $ID open
  sleep 1.2
  glide 640 330; glide 640 470; sleep 0.4
  glide 640 300; sleep 1.8

  # 2. A switch mounts a drive as a folder.
  cap "Flip a switch and the drive is a folder"
  click 912 534 0.5
  wait_until "[[ -e \"\$(demo_dir)/mounted/Work-NAS\" ]]" 20
  sleep 1.6

  # 3. What is moving, and how much room is left.
  cap "See what is uploading and how much room is left"
  glide 640 306; sleep 1.8
  glide 640 387; sleep 2.0

  # 4. Settings of one drive apply at once.
  cap "Each drive has its own settings. They apply as you change them"
  click 826 387 1.4        # OneDrive's settings
  click 301 311 0.8        # Cache
  click 882 269 1.0        # 10 GB
  click 941 311 1.0        # keep files 7 days
  click 316 271 0.8        # Behaviour
  click 980 311 1.4        # read-only on
  click 980 311 1.0        # and off again
  esc; sleep 1.0

  # 5. The keyboard.
  cap "Keyboard first. J and K move, M mounts, S opens the settings"
  typed "jjj"; sleep 0.8
  typed "m"; sleep 1.8
  typed "s"; sleep 2.2
  esc; sleep 1.0

  # 6. The app's own settings.
  cap "Settings for the app, the bar icon included"
  click 839 210 1.4
  click 294 311 0.9        # Bar
  click 980 283 1.8        # bar icon off: it leaves the bar
  click 980 283 1.8        # and on again
  click 640 170 0.5
  typed "remember"
  sleep 2.2
  esc; sleep 0.6
  esc; sleep 1.0

  # 7. Move it, resize it, and it comes back where it was left.
  cap "Resize it, move it. It opens where you left it"
  glide 949 616; sleep 0.4
  drag 110 40
  glide 700 200; sleep 0.4
  drag -150 -10
  sleep 0.4
  # Closed and straight away open again, so the bare desktop is on screen only as long as the window takes to appear.
  esc; sleep 0.15
  omarchy-shell $ID open
  sleep 1.6
  # The story ends here: closed, and the desktop is back as it was.
  esc; sleep 0.8
}
