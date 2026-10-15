# shellcheck shell=bash
# The example tour: open the card and click its button three times. Run it with ./tour tours/hello.sh (the result is left in /tmp).
TOUR_OUT=screenshots/hello.avif
TOUR_STEPS=2
TOUR_MAX_SECONDS=120

tour_play() {
  local x y
  cap "Open the card"
  omarchy-shell io.example.hello open
  wait_until "layer_up omarchy-hello" 20
  sleep 1.5
  cap "Click the button"
  read -r x y < <(omarchy-shell io.example.hello layout | jq -r '.button | "\(.x + .width / 2 | floor) \(.y + .height / 2 | floor)"')
  click "$x" "$y" 1.2; click "$x" "$y" 1.2; click "$x" "$y" 1.6
  esc; sleep 0.8
}
