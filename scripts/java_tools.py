"""Locate the JDK for shared Java synthetic checks; no Android APK builder."""
import os
from pathlib import Path
import shutil

EXE = '.exe' if os.name == 'nt' else ''


def java_tools():
    configured = os.environ.get('JAVA_HOME')
    if configured and (Path(configured) / 'bin' / ('javac' + EXE)).exists():
        return Path(configured) / 'bin'
    executable = shutil.which('javac')
    if not executable:
        raise SystemExit('JDK 17+ is required; set JAVA_HOME or add javac to PATH.')
    return Path(executable).resolve().parent
