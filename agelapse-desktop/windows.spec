# windows.spec
import os, sys, inspect, pathlib, fdlite

# -------------------------------------------------
# locate project root & import version
# -------------------------------------------------
spec_path = pathlib.Path(inspect.getfile(inspect.currentframe())).resolve()
root_dir  = spec_path.parent
sys.path.insert(0, str(root_dir))

from version import __version__ as ver
assets_dir = root_dir / "assets"

from PyInstaller.utils.win32.versioninfo import (
    FixedFileInfo, StringFileInfo, StringTable, StringStruct,
    VarFileInfo, VarStruct, VSVersionInfo
)

def make_version_info(vstr: str):
    parts = [int(p) for p in vstr.split(".")]
    parts += [0] * (4 - len(parts))
    t = tuple(parts[:4])
    return VSVersionInfo(
        ffi=FixedFileInfo(
            filevers=t,
            prodvers=t,
            mask=0x3F,
            flags=0,
            OS=0x40004,
            fileType=0x01,
            subtype=0x0,
            date=(0, 0),
        ),
        kids=[
            StringFileInfo([
                StringTable("040904B0", [
                    StringStruct("CompanyName",    "Hugo Cornellier"),
                    StringStruct("FileDescription","AgeLapse"),
                    StringStruct("FileVersion",    vstr),
                    StringStruct("InternalName",   "AgeLapse"),
                    StringStruct("OriginalFilename","AgeLapse.exe"),
                    StringStruct("ProductName",    "AgeLapse"),
                    StringStruct("ProductVersion", vstr),
                ])
            ]),
            VarFileInfo([VarStruct("Translation", [1033, 1200])]),
        ]
    )

version_info = make_version_info(ver)
# -------------------------------------------------

# absolute path to entry script
script_path = root_dir / "main.py"

# gather SVG icons (bundled as loose files, not packed)
icon_dir   = assets_dir / "icons"
icon_datas = [(str(p), "assets/icons/") for p in icon_dir.rglob("*.svg")]

a = Analysis(
    [str(script_path)],
    pathex=[str(root_dir)],                # allow absolute imports like `import src.foo`
    binaries=[],
    datas=[
        # ML models
        (os.path.join(os.path.dirname(fdlite.__file__), "data", "face_detection_back.tflite"),
         "fdlite/data/"),
        (os.path.join(os.path.dirname(fdlite.__file__), "data", "face_landmark.tflite"),
         "fdlite/data/"),
        (os.path.join(os.path.dirname(fdlite.__file__), "data", "iris_landmark.tflite"),
         "fdlite/data/"),
        # app assets
        (str(assets_dir / "images" / "agelapse.png"),          "assets/images/"),
        (str(assets_dir / "ffmpeg_win" / "ffmpeg.exe"),        "assets/ffmpeg_win/"),
        *icon_datas,
    ],
    hiddenimports=[
        "fdlite.data.face_detection_back",
        "fdlite.data.face_landmark",
        "fdlite.data.iris_landmark",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    # ---- anti-malware heuristics ----
    noarchive=False,     # keep .pyz archive (less “self-extract” noise than noarchive=True)
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [("v", None, "OPTION")],
    exclude_binaries=True,
    name=f"AgeLapse-{ver}",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch="amd64",
    version=version_info,
    icon=str(assets_dir / "1024_1024x1024.ico"),
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,          # keep UPX off for every stage
    upx_exclude=[],
    name=f"AgeLapse-{ver}",
)