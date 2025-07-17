import os, sys, inspect, pathlib, fdlite

# -------------------------------------------------
# figure out where we are & import version
# -------------------------------------------------
spec_path = pathlib.Path(inspect.getfile(inspect.currentframe())).resolve()
root_dir  = spec_path.parent.parent
sys.path.insert(0, str(root_dir))

from version import __version__ as ver
assets_dir = root_dir / "assets"
# -------------------------------------------------

# -*- mode: python ; coding: utf-8 -*-

script_path = root_dir / "main.py"     # absolute path to main.py

icon_dir   = assets_dir / 'icons'
icon_datas = [(str(p), 'assets/icons/') for p in icon_dir.rglob('*.svg')]

a = Analysis(
    [str(script_path)],
    pathex=[str(root_dir)],        # allow absolute imports like `import src.foo`
    binaries=[],
    datas=[
        (os.path.join(os.path.dirname(fdlite.__file__), 'data', 'face_detection_back.tflite'),
         'fdlite/data/'),
        (os.path.join(os.path.dirname(fdlite.__file__), 'data', 'face_landmark.tflite'),
         'fdlite/data/'),
        (os.path.join(os.path.dirname(fdlite.__file__), 'data', 'iris_landmark.tflite'),
         'fdlite/data/'),
        (str(assets_dir / 'images' / 'agelapse.png'),          'assets/images/'),
        (str(assets_dir / 'ffmpeg_mac' / 'ffmpeg'),            'assets/ffmpeg_mac/'),
        (str(assets_dir / "fonts" / "Inter-VariableFont.ttf"), "assets/fonts/"),
        *icon_datas,
    ],
    hiddenimports=[
        'fdlite.data.face_detection_back',
        'fdlite.data.face_landmark',
        'fdlite.data.iris_landmark',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=True,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [('v', None, 'OPTION')],
    exclude_binaries=True,
    name=f'AgeLapse-{ver}',
    debug=True,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch='arm64',
    codesign_identity=None,
    entitlements_file=None,
    icon=str(assets_dir / '1024_1024x1024.icns'),
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name=f'AgeLapse-{ver}',
)

app = BUNDLE(
    coll,
    name=f'AgeLapse-{ver}.app',
    icon=str(assets_dir / '1024_1024x1024.icns'),
    bundle_identifier=None,
)