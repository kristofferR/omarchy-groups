# Repository guidance

## Development and validation

- Keep the public plugin ID `kristofferr.groups` stable. Each drawer uses its own `groupId`; settings shortcuts use `role: "manager"`.
- Run `./validate` before committing. It uses the Qt 6 tools directly, runs the layout and QML tests, checks shell syntax, and validates the manifest when Omarchy is available.
- Live pointer tests are opt-in and temporarily move the cursor and modify the layout. They restore both on exit. See `docs/development.md`.
- Edit this checkout, then use `./install-local.sh` to deploy locally. Do not edit the packaged Omarchy source.

## Release workflow

- Treat `manifest.json` as the release source of truth and bump its semantic version for every published release.
- Keep the icon and `preview.png` current with the implemented UI. Put future demo videos/GIFs in GitHub release assets so clones stay small.
- Preserve Nook's MIT copyright notice and credit when changing the branding or documentation.
- Fleet auto-review is intentionally not enabled for this repository.
- Keep guidance in `AGENTS.md` only: Omarchy plugin validation rejects symlinks, including a `CLAUDE.md` alias.
