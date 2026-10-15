# shellcheck shell=bash
# A short clip of the app's own settings window, cropped from the session: its pages, the bar icon switched off and on,
# and the search box, ending where it began so that the animation loops. Run it with
# scripts/tour.sh scripts/tours/app-app-settings-clip.sh [--install].
#
# It runs on the demo drives of lib/demo.sh, in a sandbox, like the hero tour (see scripts/tours/hero.sh).

TOUR_OUT=screenshots/app-settings-clip.avif
# The window at its default size, centred on the screen, with a 40 px margin of backdrop (as screenshots.sh crops it).
TOUR_CROP=840x600+220+100
# A flat backdrop, so no wallpaper shows around the window.
TOUR_BACKDROP=plain
TOUR_BG='#2a2f3a'
TOUR_MAX_SECONDS=120

ID=io.github.bmaltais.startdrive

tour_prepare() {
  "$REPO/bin/startdrive" window --reset >/dev/null
  "$REPO/bin/startdrive" window --reset-setup >/dev/null
}

# The window is already open when filming starts, so the clip begins and ends on the same picture.
tour_setup() {
  omarchy-shell $ID setup
  sleep 2
}

tour_play() {
  sleep 1.2
  click 294 311 1.0        # Bar
  click 980 283 1.6        # bar icon off
  click 980 283 1.6        # and on again
  click 640 170 0.5        # the search box
  typed "remember"
  sleep 2.0
  esc; sleep 1.0           # clears the search
  click 294 271 1.0        # back to General, where it began
  glide 640 560; sleep 0.8
}
