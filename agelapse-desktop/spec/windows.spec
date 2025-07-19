import os, sys, inspect, pathlib, fdlite

# locate project root
spec_path = pathlib.Path(inspect.getfile(inspect.currentframe())).resolve()
root_dir  = spec_path.parent.parent
sys.path.insert(0, str(root_dir))

from version import __version__ as ver
assets_dir = root_dir / 'assets'
icon_dir   = assets_dir / 'icons'
icon_datas = [(str(p), 'assets/icons/') for p in icon_dir.rglob('*.svg')]

a = Analysis(
    [str(root_dir / 'main.py')],
    pathex=[str(root_dir)],
    binaries=[],
    datas=[
        # fdlite models
        (os.path.join(os.path.dirname(fdlite.__file__), 'data', 'face_detection_back.tflite'),
         'fdlite/data/'),
        (os.path.join(os.path.dirname(fdlite.__file__), 'data', 'face_landmark.tflite'),
         'fdlite/data/'),
        (os.path.join(os.path.dirname(fdlite.__file__), 'data', 'iris_landmark.tflite'),
         'fdlite/data/'),
        # your assets
        (str(assets_dir / 'images' / 'agelapse.png'),  'assets/images/'),
        (str(assets_dir / 'ffmpeg_win' / 'ffmpeg.exe'), 'assets/ffmpeg_win/'),
        (str(assets_dir / 'fonts' / 'Inter-VariableFont.ttf'), 'assets/fonts/'),
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
    a.binaries,
    a.zipfiles,
    a.datas,
    name=f'AgeLapse-{ver}',
    debug=False,
    console=False,
    icon=str(assets_dir / '256x256.ico'),
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    runtime_tmpdir=None,
)