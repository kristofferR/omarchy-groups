# Groups for Omarchy

Organize your Omarchy bar into independent icon groups. Drawers open below the bar, so your other icons stay in place. Drag widgets into groups, back onto the bar, or directly between groups.

![Groups settings](preview.png)

## Highlights

- **Independent groups.** Give each drawer a name, icon, and stable identity. Place groups on the left, center, or right.
- **A steady bar.** Drawers open below the bar without pushing other icons around.
- **Drag and drop.** Move widgets between the bar and groups, reorder inside a drawer, or transfer directly between groups. Widget settings stay with the icon.
- **Native interactions.** Hosted plugins keep their hover tooltips, right-click actions, scrolling, and popup panels.
- **Hover or click.** Hover opens a drawer; click pins it. Click again or outside to dismiss.
- **Built for Omarchy.** Uses the shell's active theme and existing plugin widgets, with no extra background service.

## Requirements

- Omarchy Quattro with the native shell plugin system
- The standard Omarchy bar

The underlying Quickshell and Hyprland support ships with Omarchy. The top bar is the supported and verified configuration.

## Install

```sh
omarchy plugin add https://github.com/kristofferR/omarchy-groups.git --enable
```

Drag an existing bar icon onto the new group to get started. Use **Add group** in settings to create more groups. For manual configuration, add entries to `bar.layout.left`, `center`, or `right` in `~/.config/omarchy/shell.json`:

```json
{
  "id": "kristofferr.groups",
  "groupId": "devices",
  "label": "Connections & devices",
  "icon": "devices",
  "trigger": "hover",
  "duration": 0,
  "items": []
}
```

The settings panel creates unique group IDs automatically. For hand-written entries, every group needs a unique, stable `groupId`. Available icons are `windows`, `development`, `input`, `sound`, `devices`, `display`, `appearance`, `maintenance`, and `group`.

Start with empty groups and drag widgets into them. Dragging manages plugin enablement and preserves settings automatically. When configuring `items` by hand, keep the hosted plugins enabled through the top-level `plugins` array, preserving any existing service settings.

### Update

```sh
omarchy plugin update kristofferr.groups --yes
```

### Remove

Drag the icons you want to keep back onto the bar first, then:

```sh
omarchy plugin remove kristofferr.groups --yes
```

## Controls

| Action | Result |
| --- | --- |
| Hover a group | Open its drawer |
| Click a group | Pin it open; click again to close |
| Click outside | Dismiss the drawer |
| Right-click a group | Open Groups settings |
| Drag a bar icon onto a group | Move it into the drawer |
| Drag within a drawer | Reorder icons |
| Drag to another group | Transfer the widget and its settings |
| Drag to a position on the bar | Place the widget there |
| Drop outside the bar and drawers | Cancel the move |

Opening another group closes the previous drawer and its child panel. A widget's own panel keeps its group open while in use. Nested groups are not supported.

## Settings

Right-click any group to open the shared settings panel. Select a group, change its name, pick an icon, choose left/center/right placement and hover/click opening, then press **Save changes**. Edits preserve hosted widgets and their settings.

**Add group** creates an empty drawer ready for icons. **Remove group** returns its widgets to the same bar section, preserving their settings. The settings shortcut is kept separate from the editable groups.

An optional dedicated settings icon uses this bar entry:

```json
{"id": "kristofferr.groups", "groupId": "settings", "role": "manager", "label": "Groups settings"}
```

Open the same panel from the terminal:

```sh
omarchy-shell shell summon kristofferr.groups
```

Escape, Done, or clicking outside closes settings. Avoid the stock per-widget settings editor for multiple instances: it looks up widgets by plugin ID and cannot reliably distinguish individual groups.

Groups also expose independent IPC controls:

```sh
omarchy-shell kristofferr.groups.devices open
omarchy-shell kristofferr.groups.devices close
omarchy-shell kristofferr.groups.devices toggle
omarchy-shell kristofferr.groups.devices status
omarchy-shell kristofferr.groups.devices absorb omarchy.network
omarchy-shell kristofferr.groups.devices eject omarchy.network
omarchy-shell kristofferr.groups.devices reorder 0 2
```

Replace `devices` with your group ID. The `eject` command places the widget beside its group; dragging lets you choose the position.

## Development

```sh
./validate
./install-local.sh
```

Validation runs layout tests, Qt 6 lint, the Quickshell harness, shell syntax checks, and manifest validation when Omarchy is installed. The local installer copies runtime files into the user plugin directory and restarts the shell to clear cached QML components. It does not change the layout.

See [development notes](docs/development.md) for optional live pointer tests, hosting limitations, and the original base/separator comparison.

## Security and system changes

Groups runs inside Omarchy Shell with your user's permissions. Moving widgets updates `~/.config/omarchy/shell.json`, including the plugin enablement entries required by hosted widgets. It does not install packages or change Hyprland configuration. Hosted plugins retain their own behavior and permissions.

## Troubleshooting

- **Empty drawer:** drag an icon onto the group. An empty group has no drawer content to display.
- **Widget missing:** verify the plugin is installed and enabled. Some plugins hide their icon while idle or when hardware is absent.
- **Changes do not appear:** run `omarchy plugin validate .` in the checkout. After replacing plugin code manually, restart the shell with `omarchy restart shell` to clear cached hosted components.
- **Several groups behave unexpectedly:** check that every `groupId` is unique. Config edits refuse ambiguous group identities.

## Credits

Based on [Nook](https://github.com/Katsari/nook) by Katsari, starting from version 1.1.2. Its widget hosting, panel anchoring, scrolling, original drag handling, and Git history are preserved.

## License

MIT
