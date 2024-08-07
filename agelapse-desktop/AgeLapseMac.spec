# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('/usr/local/lib/python3.10/site-packages/fdlite/data/face_detection_back.tflite', 'fdlite/data/'),
        ('/usr/local/lib/python3.10/site-packages/fdlite/data/face_landmark.tflite', 'fdlite/data/'),
        ('/usr/local/lib/python3.10/site-packages/fdlite/data/iris_landmark.tflite', 'fdlite/data/'),
        ('assets/images/agelapse.png', 'assets/images/'),
        ('assets/ffmpeg_mac/ffmpeg', 'assets/ffmpeg_mac/')
    ],
    hiddenimports=[
        'fdlite.data.face_detection_back',
        'fdlite.data.face_landmark',
        'fdlite.data.iris_landmark'
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
    name='AgeLapse',
    debug=True,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='assets/1024_1024x1024.icns'  # Set the path to your .icns file here
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='AgeLapse',
)

app = BUNDLE(
    coll,
    name='AgeLapse.app',
    icon='assets/1024_1024x1024.icns',  # Set the path to your .icns file here
    bundle_identifier=None,
)
