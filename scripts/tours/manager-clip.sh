# shellcheck shell=bash
# A short clip of the manager window, cropped from the session: a drive is mounted as a folder with its switch and
# unmounted again, with the pointer going over the rows, so that the animation loops. Run it with
# scripts/tour.sh scripts/tours/manager-clip.sh [--install].
#
# It runs on the demo drives of lib/demo.sh, in a sandbox, like the hero tour (see scripts/tours/hero.sh).

TOUR_TITLE=StartDrive
TOUR_OUT=screenshots/manager-clip.avif
TOUR_LAYER=omarchy-startdrive
# The window at its default size, centred on the screen, with a 40 px margin of backdrop (as screenshots.sh crops it).
TOUR_CROP=720x540+280+130
# A flat backdrop, so no wallpaper shows around the window.
TOUR_BACKDROP=plain
TOUR_BG='#2a2f3a'
TOUR_MAX_SECONDS=120

TOUR_PLUGIN_ID=io.github.bmaltais.startdrive
TOUR_SANDBOX_COPY=()
TOUR_SANDBOX_LINK=(.local/share/icons)
TOUR_REAL_UNCHANGED=(.config/omarchy/shell.json .config/startdrive .config/systemd/user .config/rclone .local/share/applications/startdrive.desktop .local/bin/startdrive)

ID=io.github.bmaltais.startdrive
# Worked out when used, so that (HOME being the sandbox) it is the sandbox's.
demo_dir() { echo "$HOME/.config/startdrive/demo"; }

tour_prepare() {
  "$REPO/bin/startdrive" window --reset >/dev/null
  "$REPO/bin/startdrive" window --reset-setup >/dev/null
}

# The window is already open when filming starts, so the clip begins and ends on the same picture.
tour_setup() {
  omarchy-shell $ID open
  sleep 2
}

tour_play() {
  glide 640 330; glide 640 470; sleep 0.4
  glide 640 300; sleep 1.6
  click 912 534 0.5        # Work-NAS: mount it
  wait_until "[[ -e \"\$(demo_dir)/mounted/Work-NAS\" ]]" 20
  sleep 1.8
  glide 640 387; sleep 1.6
  click 912 534 0.5        # and unmount it again
  wait_until "[[ ! -e \"\$(demo_dir)/mounted/Work-NAS\" ]]" 20
  sleep 1.2
  glide 640 560; sleep 0.8
}
