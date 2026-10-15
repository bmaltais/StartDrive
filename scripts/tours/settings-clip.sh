# shellcheck shell=bash
# A short clip of one drive's settings window, cropped from the session: the pages are flipped through and a few
# settings changed, ending where it began so that the animation loops. A clip like this replaces a still image in the
# README. Run it with scripts/tour.sh scripts/tours/settings-clip.sh [--install].
#
# It runs on the demo drives of lib/demo.sh, in a sandbox, like the hero tour (see scripts/tours/hero.sh).

TOUR_TITLE=StartDrive
TOUR_OUT=screenshots/settings-clip.avif
TOUR_LAYER=omarchy-startdrive
# The settings window at its default size, centred on the screen, with a 40 px margin of backdrop (as screenshots.sh crops it).
TOUR_CROP=840x600+220+100
# A flat backdrop, so no wallpaper shows around the window.
TOUR_BACKDROP=plain
TOUR_BG='#2a2f3a'
TOUR_MAX_SECONDS=120

TOUR_PLUGIN_ID=io.github.bmaltais.startdrive
TOUR_SANDBOX_COPY=()
TOUR_SANDBOX_LINK=(.local/share/icons)
TOUR_REAL_UNCHANGED=(.config/omarchy/shell.json .config/startdrive .config/systemd/user .config/rclone .local/share/applications/startdrive.desktop .local/bin/startdrive)

ID=io.github.bmaltais.startdrive

tour_prepare() {
  "$REPO/bin/startdrive" window --reset >/dev/null
  "$REPO/bin/startdrive" window --reset-setup >/dev/null
}

# The window is already open when filming starts, so the clip begins and ends on the same picture.
tour_setup() {
  omarchy-shell $ID settings onedrive
  sleep 2
}

tour_play() {
  sleep 1.2
  click 980 311 1.2        # Behaviour: read-only on
  click 980 311 1.0        # and off again
  click 316 311 1.0        # Cache
  click 882 269 1.2        # 10 GB
  click 941 311 1.2        # keep files 7 days
  click 316 351 1.4        # Maintenance
  click 316 271 1.0        # back to Behaviour, where it began
  glide 640 560; sleep 0.8
}
