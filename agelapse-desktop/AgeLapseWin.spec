# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=[], 
    datas=[ 
        ('C:\\Users\\hugo\\AppData\\Local\\Programs\\Python\\Python312\\Lib\\site-packages\\fdlite\\data\\face_detection_back.tflite', 'fdlite/data/'),
        ('C:\\Users\\hugo\\AppData\\Local\\Programs\\Python\\Python312\\Lib\\site-packages\\fdlite\\data\\face_landmark.tflite', 'fdlite/data/'),
        ('C:\\Users\\hugo\\AppData\\Local\\Programs\\Python\\Python312\\Lib\\site-packages\\fdlite\\data\\iris_landmark.tflite', 'fdlite/data/'),
        ('assets/ffmpeg_win/ffmpeg.exe', 'assets/ffmpeg_win/'),
        ('assets/images/agelapse.png', 'assets/images/'),
    ],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries + a.datas,
    exclude_binaries=False,
    name='AgeLapse',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,  # Set to False for no console window
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='assets/256x256.ico'
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='AgeLapse'
)
