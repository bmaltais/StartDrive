// A tiny virtual-pointer client: moves and clicks a Wayland compositor's pointer over its own socket
// (WAYLAND_DISPLAY), so input reaches that compositor and no other. Used by the tour recorder to drive a
// nested session that your own mouse cannot touch. ydotool cannot do this: it writes to the kernel, which
// only reaches your real seat.
//
//   vptr move X Y W H        put the pointer at X,Y on an output W by H pixels
//   vptr click X Y W H       move there, press and release the left button
//   vptr press X Y W H       move there, press the left button
//   vptr release X Y W H     move there, release the left button
//   vptr drag X Y W H DX DY  move there, press the left button, move by DX,DY in ten steps, release
//   vptr rclick X Y W H      move there, press and release the right button
//   vptr scroll X Y W H N    move there, turn the wheel N notches (positive scrolls down, negative up)
//
// Built with lib/build-vptr.sh.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;

static void global(void *data, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t version) {
  (void)data; (void)version;
  if (!strcmp(iface, wl_seat_interface.name)) seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
  else if (!strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name))
    manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void global_remove(void *data, struct wl_registry *reg, uint32_t name) { (void)data; (void)reg; (void)name; }
static const struct wl_registry_listener listener = { global, global_remove };

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(int argc, char **argv) {
  if (argc != 6 && argc != 7 && argc != 8) { fprintf(stderr, "usage: vptr move|click|rclick|press|release X Y W H | scroll X Y W H N | drag X Y W H DX DY\n"); return 2; }
  const char *verb = argv[1];
  uint32_t x = (uint32_t)atoi(argv[2]), y = (uint32_t)atoi(argv[3]), w = (uint32_t)atoi(argv[4]), h = (uint32_t)atoi(argv[5]);

  struct wl_display *display = wl_display_connect(NULL);
  if (!display) { fprintf(stderr, "vptr: cannot connect to WAYLAND_DISPLAY\n"); return 1; }
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &listener, NULL);
  wl_display_roundtrip(display);
  if (!manager) { fprintf(stderr, "vptr: the compositor has no virtual-pointer protocol\n"); return 1; }

  struct zwlr_virtual_pointer_v1 *ptr = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
  zwlr_virtual_pointer_v1_motion_absolute(ptr, now_ms(), x, y, w, h);
  zwlr_virtual_pointer_v1_frame(ptr);
  const uint32_t BTN_LEFT = 0x110, BTN_RIGHT = 0x111;
  if (!strcmp(verb, "rclick")) {
    wl_display_roundtrip(display);
    usleep(60000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_RIGHT, WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(ptr);
    wl_display_roundtrip(display);
    usleep(60000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_RIGHT, WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(ptr);
  }
  if (!strcmp(verb, "scroll") && argc == 7) {
    // One notch is 15 units of smooth scrolling and one discrete step, as a wheel sends them; a pause between notches.
    int n = atoi(argv[6]), dir = n < 0 ? -1 : 1;
    wl_display_roundtrip(display);
    for (int i = 0; i < abs(n); i++) {
      usleep(70000);
      zwlr_virtual_pointer_v1_axis_source(ptr, WL_POINTER_AXIS_SOURCE_WHEEL);
      zwlr_virtual_pointer_v1_axis_discrete(ptr, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(15 * dir), dir);
      zwlr_virtual_pointer_v1_frame(ptr);
      wl_display_roundtrip(display);
    }
  }
  if (!strcmp(verb, "drag") && argc == 8) {
    int dx = atoi(argv[6]), dy = atoi(argv[7]);
    wl_display_roundtrip(display);
    usleep(80000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(ptr);
    // Eased (slow, quick, slow), with the odd pixel of wobble and an uneven pace, like a hand.
    srand((unsigned)now_ms());
    for (int i = 1; i <= 14; i++) {
      double t = i / 14.0, e = t * t * t * (10 - 15 * t + 6 * t * t);   /* minimum jerk */
      int wx = (i < 14) ? rand() % 3 - 1 : 0, wy = (i < 14) ? rand() % 3 - 1 : 0;
      wl_display_roundtrip(display);
      usleep(35000 + (unsigned)(rand() % 40000));
      zwlr_virtual_pointer_v1_motion_absolute(ptr, now_ms(), (uint32_t)((int)x + (int)(dx * e) + wx), (uint32_t)((int)y + (int)(dy * e) + wy), w, h);
      zwlr_virtual_pointer_v1_frame(ptr);
    }
    wl_display_roundtrip(display);
    usleep(80000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(ptr);
  }
  if (!strcmp(verb, "click") || !strcmp(verb, "press")) {
    wl_display_roundtrip(display);
    usleep(60000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(ptr);
  }
  if (!strcmp(verb, "click") || !strcmp(verb, "release")) {
    wl_display_roundtrip(display);
    usleep(60000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(ptr);
  }
  wl_display_roundtrip(display);
  zwlr_virtual_pointer_v1_destroy(ptr);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  return 0;
}
