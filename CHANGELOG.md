# Changelog

## 1.1.1

- Keep icon selection and settings navigation working without a focus error.
- Allow Groups to return to the bar after removing a group.
- Reorder the intended group when several groups share the bar, and leave the layout unchanged when a drag is canceled.

## 1.1.0

- Reduce work during drawer updates and hovers, and load picker models only while settings are open.
- Cache icon search data for faster repeated searches.
- Keep overflow scrolling consistent across refresh rates and update drop positions while scrolling.
- Preserve the exact selected widget and its settings during drag-and-drop, reject stale drag sources, and retain enablement for widgets still hosted elsewhere.
- Close the source drawer after a transfer so it cannot block clicks on the destination.

## 1.0.1

- Preserve each repeated widget's settings when moving a selected instance from a group to the bar or another group.
- Generate icon catalogs with explicit UTF-8 encoding.

## 1.0.0

First public release of Groups for Omarchy.

- Independent named groups with searchable icons and hover or click opening.
- Complete setup and widget management in the settings UI, without JSON editing.
- Drag widgets into, out of, and between groups while preserving their settings.
- Native tooltips, right-click actions, scrolling, and popup panels.
- Stable bar and drawer widgets during layout changes, with automatic stock-bar compatibility.
- Smooth hover and drag handoff without icons blanking or drawers blinking after a drop.

Groups uses the existing `kristofferr.groups` plugin ID. Existing group layouts and
settings are retained. The development version is reset to 1.0.0 for this first
release; installation and updates follow Git commits rather than version order.
