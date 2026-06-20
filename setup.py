from setuptools import setup

APP = ["pingslut.py"]
DATA_FILES = []
OPTIONS = {
    "argv_emulation": False,
    "packages": ["ping3"],
    "includes": ["matplotlib.backends.backend_tkagg"],
    "plist": {
        "CFBundleName": "PingSlut",
        "CFBundleDisplayName": "PingSlut",
        "CFBundleIdentifier": "com.pingslut.app",
        "CFBundleVersion": "1.0.0",
        "CFBundleShortVersionString": "1.0.0",
        "NSHighResolutionCapable": True,
    },
}

setup(
    app=APP,
    name="PingSlut",
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
