# Groups for Omarchy

Independent, named icon groups that open directly below the bar. A fork of
[Katsari/Nook](https://github.com/Katsari/nook), based on version 1.1.2.
The existing widget hosting, panel anchoring, scrolling and drag handling come
from Nook. The MIT license and upstream history are preserved.

Each group has a boxed icon, a configured name, and a unique `groupId`. Hover-open
groups show their hover title below the drawer so it cannot cover the icons. Opening a
group closes the previous group and its open child panel. The bar stays one row:
opening a drawer does not move any bar icons. Hover opens the drawer; click pins
it; click again closes it. Clicking outside, including empty bar space, dismisses
the group. A child's panel keeps its drawer open while in use; dismissing that
panel closes its group too. Widgets of different heights are centered in the drawer.
Reveal animation is off by default.

## Local development and installation

```sh
bash tests/all.sh
./install-local.sh
```

The installer validates and copies the runtime files into
`~/.config/omarchy/plugins/kristofferr.groups`, then restarts the shell once to clear cached hosted QML components. It does not
change the layout. Edit this checkout and rerun the installer to deploy changes;
the installed copy is deliberately not managed by upstream plugin updates.

Add any number of entries to `bar.layout.left`, `center`, or `right`:

```json
{
  "id": "kristofferr.groups",
  "groupId": "devices",
  "label": "Connections & devices",
  "icon": "devices",
  "trigger": "hover",
  "duration": 0,
  "items": [
    { "id": "omarchy.bluetooth" },
    { "id": "omarchy.tailscale" }
  ]
}
```

Also keep hosted plugins enabled through top-level `plugins` entries, for example
`{"id":"omarchy.bluetooth"}`. Preserve existing service settings on those entries.
The drawer's absorb/eject commands manage enablement automatically. Per-widget
layout settings stay with the widget when it moves.

Icon names: `windows`, `development`, `input`, `sound`, `devices`, `display`,
`appearance`, `maintenance`, or `group`. SVGs use a fixed viewbox and centered
14-pixel image in a 28-pixel slot so glyph bearings cannot shift them within their buttons.

Every group needs a unique, stable `groupId`. Missing or duplicate IDs will never
silently redirect config edits into a sibling. An unnamed single group remains
supported, but named groups are required for multiple instances. Configure group
entries directly in `shell.json`: the stock settings editor searches by plugin
ID, so it cannot reliably distinguish multiple instances of any plugin.

## Controls

```sh
omarchy-shell kristofferr.groups.devices open
omarchy-shell kristofferr.groups.devices close
omarchy-shell kristofferr.groups.devices toggle
omarchy-shell kristofferr.groups.devices status
omarchy-shell kristofferr.groups.devices absorb omarchy.network
omarchy-shell kristofferr.groups.devices eject omarchy.network
omarchy-shell kristofferr.groups.devices reorder 0 2
```

Drag a bar widget onto a group to absorb it, reorder within the drawer, or drag
it back onto the bar to eject it. To move between groups, eject then absorb.
Nested groups are intentionally unsupported. Each group's IPC target and config
writes are independent. Status includes the group identity, live child load
state, and geometry for diagnostics.

## Why this base and which separators?

Research checked on 2026-09-07:

| Option | Fit for this layout |
| --- | --- |
| [Nook 1.1.2](https://github.com/Katsari/nook) | Closest fit: actual widgets in an anchored strip below the existing bar. Upstream supports one drawer; this fork adds independent instances. |
| [Skål Bar](https://github.com/outcrop-labs/skal-bar) | Replaces the full bar with reveal controls for its three regions. More replacement code than needed for several independent drawers. |
| [OmaBar Drawer](https://github.com/amitcpatel/omabar-drawer) | Full-bar replacement that collapses the right region behind one icon. |
| [Plugin Drawer](https://github.com/alyayman921/Omarchy-drawer) | Single drawer with a grid/list interface. A different presentation from the small strips wanted here. |
| [Bar Studio](https://github.com/andreconde21/omarchy-bar-studio) | Layout editor, not a multiple-drawer host. Its tray collapse needs a compatible tray; the stock tray does not display its hosted array. |
| Stock `omarchy.spacer` | Built-in blank spacing, repeatable with configurable `size`. |
| [Bar Divider 1.1.0](https://github.com/Rizmi/omarchy-divider-plugin) | Existing repeatable line, dot or pipe separators. Reused unchanged for the live layout. |

Example separator: `{"id":"io.github.rizmi.divider","style":"line","margin":5}`.

## Validation and boundaries

`tests/all.sh` runs the pure layout tests, Qt 6 lint, manifest validation and a
Quickshell harness. The harness exercises separate instance config writes,
settings retention, open/close isolation and sibling closing. Pure tests also
cover absent/duplicate IDs and every group-scoped mutation.

Optional real-pointer drag tests require `tests/tools/vptr/build.sh` and
`NOOK_GROUP_ID=<group> bash tests/all.sh --drag`. They temporarily modify and
restore the live layout, so run them only while the pointer is free.

Nook integrates with Omarchy's bar internals rather than a stable hosting API.
Top-bar behavior is the supported and verified configuration here. Some widgets
hide themselves when idle or when hardware is absent; their slots are still
loaded. Widgets retain their own tooltip and status behavior. The group trigger
does not aggregate every plugin's urgency state.
