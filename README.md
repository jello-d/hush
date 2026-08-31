# hush

A small notifications suite for a Wayland session running [mako](
https://github.com/emersion/mako): a trinary filter, per-display placement, and
an SNI tray icon for the filter state.

- **`dnd-comms-toggle`** cycles a trinary, application-based filter over mako:
  **all** flow, only **work** flow (personal muted), or **none**. What counts as
  work vs personal is a mako rule (e.g. Slack vs Signal) -- hush carries no
  notion of a work account or identity boundary.
- **`mako-placement`** writes mako's `placement.active` include for the current
  display. It reads a per-shape config and the display density when a shape
  resolver is present, and falls back to a shipped single-output default
  otherwise (both are optional soft dependencies).
- **`comms-indicator`** is an SNI tray icon (an owned glyph, frame colour =
  state); left-click cycles the filter. It runs as a `--user` service.

## Install

```sh
git clone https://github.com/jello-d/hush ~/.hush
~/.hush/setup.sh install     # the shell tools + man + the mako config
~/.hush/setup.sh service     # + the tray icon (a venv-backed --user daemon)
# or: ~/.hush/setup.sh all
```

`install` is the shell mechanism + config (what a provisioning layer delegates
to); `service` is kept separate because the tray icon is a Python/D-Bus daemon
(it builds its own venv -- no external runner needed). `setup.sh check` audits
the install; `setup.sh uninstall` reverses it.

## Dependencies

`mako` + `makoctl` (the filter drives mako), and a StatusNotifierItem tray host
for the icon (waybar's tray, or any desktop's). Optional: a display-shape
resolver (e.g. kanshi-autoscale) for per-shape placement/sizing; absent, hush
uses its single-output default. The tray icon's Python deps (`dbus-next`,
`Pillow`) are pulled into the venv by `setup.sh service`.

POSIX shell throughout, except the tray daemon (Python); no daemon in the core.
Apache-2.0.
