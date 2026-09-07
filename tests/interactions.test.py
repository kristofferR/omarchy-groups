#!/usr/bin/env python3
"""Opt-in live pointer test. Restores the configuration and pointer on exit."""
import importlib.util
import json
import os
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('drag', ROOT / 'tests/drag.test.py')
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)
PROBE = 'group-interaction-probe'
SOURCE = os.environ.get('NOOK_GROUP_ID', 'windows')
DEST = os.environ.get('NOOK_TARGET_GROUP_ID', 'input')
d.TARGET = 'kristofferr.groups.' + SOURCE
config_path = Path.home() / '.config/omarchy/shell.json'

def config(): return json.loads(config_path.read_text())
def group(name, cfg=None):
    return next(e for es in (cfg or config())['bar']['layout'].values() for e in es
                if e['id'] == 'kristofferr.groups' and e.get('groupId') == name)
def ids(name): return [e['id'] if isinstance(e, dict) else e for e in group(name)['items']]
def ipc(name, method): return d.sh('omarchy-shell', 'kristofferr.groups.' + name, method)
def state(name): return json.loads(ipc(name, 'status'))
def gpoint(name):
    s = state(name)
    return round(s['x'] + s['width'] / 2), 13

def probe_state(): return json.loads(d.sh('omarchy-shell', PROBE, 'status'))
def wait(predicate, message): d.wait_for(predicate, message)

def main():
    original = config_path.read_text()
    original_cursor = json.loads(d.sh('hyprctl', 'cursorpos', '-j'))
    cfg = json.loads(original)
    group(SOURCE, cfg)
    group(DEST, cfg)
    fixture = {'id': PROBE, 'source': str(ROOT / 'tests/fixtures/NativeProbe.qml'), 'testSetting': 'preserved'}
    cfg['bar']['layout']['left'].append(fixture)
    mouse = d.Pointer()
    try:
        config_path.write_text(json.dumps(cfg, indent=2) + '\n')
        wait(lambda: PROBE in d.geometry(), 'probe loads')
        mouse.move((700,300), dwell=300)
        mouse.move(d.center(d.geometry()[PROBE]), dwell=700)
        before = probe_state()
        mouse.send(('dr',), ('s',80), ('ur',), ('s',200))
        assert probe_state()['right'] == before['right'] + 1
        print('native right click works on bar', flush=True)

        mouse.drag(d.center(d.geometry()[PROBE]), gpoint(SOURCE))
        wait(lambda: PROBE in ids(SOURCE), 'bar to source group')
        print('bar → group', flush=True)
        mouse.move((700,300), dwell=400)
        mouse.move(gpoint(SOURCE), dwell=600)
        wait(lambda: state(SOURCE)['expanded'], 'source drawer opens on hover')
        wait(lambda: d.geometry()[PROBE]['y'] >= 26, 'probe below bar')
        target = d.item_center(d.geometry()[PROBE])
        # Enter the drawer vertically before moving across to a distant icon.
        entry = (gpoint(SOURCE)[0], target[1])
        mouse.glide(gpoint(SOURCE), entry)
        wait(lambda: state(SOURCE)['hoverHeld'], 'pointer enters hover-open drawer')
        mouse.glide(entry, target)
        mouse.move(d.item_center(d.geometry()[PROBE]), dwell=700)
        wait(lambda: state(SOURCE)['childTooltipVisible'], 'native tooltip shown in group')
        assert state(SOURCE)['childTooltipText'] == 'Native probe tooltip'
        before = probe_state()
        mouse.send(('dr',), ('s',80), ('ur',), ('s',200))
        assert probe_state()['right'] == before['right'] + 1
        assert probe_state()['left'] == before['left']
        print('native hover tooltip and right click work inside group', flush=True)

        ipc(SOURCE, 'open')
        first = d.geometry()[ids(SOURCE)[0]]
        mouse.drag(d.item_center(d.geometry()[PROBE]), (first['x'] + 1, d.item_center(first)[1]))
        wait(lambda: ids(SOURCE)[0] == PROBE, 'reorder within group')
        print('reorder within group', flush=True)

        # Config reload reconstructs the drawer after a reorder.
        mouse.move((700,300), dwell=400)
        mouse.move(gpoint(SOURCE), dwell=500)
        ipc(SOURCE, 'open')
        wait(lambda: d.geometry()[PROBE]['y'] >= 26, 'reordered probe below bar')
        mouse.glide(gpoint(SOURCE), d.item_center(d.geometry()[PROBE]))

        # Transfer in one drag, without an intermediate placement on the bar.
        mouse.drag(d.item_center(d.geometry()[PROBE]), gpoint(DEST))
        wait(lambda: PROBE in ids(DEST), 'source to destination group')
        assert PROBE not in ids(SOURCE)
        assert next(e for e in group(DEST)['items'] if e['id'] == PROBE) == fixture
        print('group → different group, settings retained', flush=True)

        mouse.move((700,300), dwell=400)
        mouse.move(gpoint(DEST), dwell=500)
        ipc(DEST, 'open')
        wait(lambda: d.geometry()[PROBE]['y'] >= 26, 'probe below bar')
        mouse.glide(gpoint(DEST), d.item_center(d.geometry()[PROBE]))
        # Drop immediately before the clock in a different region from SOURCE.
        clock = d.geometry()['omarchy.clock']
        mouse.drag(d.item_center(d.geometry()[PROBE]), (clock['x'] + 2, 13))
        wait(lambda: PROBE not in ids(DEST), 'group to exact bar slot')
        right = config()['bar']['layout']['right']
        probe_index = next(i for i,e in enumerate(right) if e['id'] == PROBE)
        assert right[probe_index+1]['id'] == 'omarchy.clock', 'drop must land before clock'
        assert right[probe_index] == fixture
        print('group → precise bar slot, settings retained', flush=True)

        mouse.drag(d.center(d.geometry()[PROBE]), gpoint(DEST))
        wait(lambda: PROBE in ids(DEST), 'bar back into group')
        mouse.move((700,300), dwell=400)
        mouse.move(gpoint(DEST), dwell=500)
        ipc(DEST, 'open')
        wait(lambda: d.geometry()[PROBE]['y'] >= 26, 'probe below bar')
        mouse.glide(gpoint(DEST), d.item_center(d.geometry()[PROBE]))
        before = config_path.read_text()
        mouse.drag(d.item_center(d.geometry()[PROBE]), (700,300))
        assert config_path.read_text() == before, 'drop outside bar/drawers must cancel'
        print('outside drop cancels without a config edit', flush=True)
    finally:
        mouse.send(('u',), ('ur',))
        config_path.write_text(original)
        time.sleep(1)
        mouse.move((original_cursor['x'], original_cursor['y']), dwell=100)
        mouse.close()
        print('original layout and pointer restored', flush=True)

if __name__ == '__main__': main()
