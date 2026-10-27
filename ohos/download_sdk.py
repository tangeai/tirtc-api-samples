#!/usr/bin/env python3
"""Download the exact HAR from sdk.json and verify it before replacing a file."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import time
import urllib.request


def validate_metadata(metadata, version=None):
    if not isinstance(metadata, dict):
        raise ValueError('sdk.json must contain a JSON object')
    selected = metadata.get('version')
    if not isinstance(selected, str) or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(?:alpha|beta)\.(0|[1-9]\d*))?', selected):
        raise ValueError('SDK version must be the exact stable/alpha/beta version')
    if version is not None and selected != version:
        raise ValueError('SDK version differs from the requested release')
    if metadata.get('url') != f'https://github.com/tangeai/tirtc-sdk-ohos/releases/download/v{selected}/tirtc.har':
        raise ValueError('SDK URL must identify the exact public OHOS GitHub release')
    size, expected = metadata.get('size'), metadata.get('sha256')
    if type(size) is not int or size <= 0 or size > 1024 * 1024 * 1024:
        raise ValueError('SDK size is outside the bounded download contract')
    if not isinstance(expected, str) or not re.fullmatch(r'[0-9a-f]{64}', expected):
        raise ValueError('SDK SHA-256 is invalid')
    return metadata


def digest_file(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def download(root: Path) -> Path:
    metadata = validate_metadata(json.loads((root / 'sdk.json').read_text()))
    size, expected = metadata['size'], metadata['sha256']
    target = root / 'vendor/tirtc.har'
    if target.parent.is_symlink() or target.is_symlink():
        raise ValueError('SDK destination must not be a symlink')
    if target.is_file() and target.stat().st_size == size and digest_file(target) == expected:
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix='.download-', dir=target.parent)
    temporary = Path(name)
    try:
        digest, total = hashlib.sha256(), 0
        deadline = time.monotonic() + 300
        with os.fdopen(descriptor, 'wb') as output, urllib.request.urlopen(metadata['url'], timeout=60) as response:
            while chunk := response.read(1024 * 1024):
                if time.monotonic() > deadline:
                    raise TimeoutError('HAR download exceeded its five-minute budget')
                total += len(chunk)
                if total > size:
                    raise ValueError('downloaded HAR exceeds its frozen size')
                digest.update(chunk)
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        if total != size or digest.hexdigest() != expected:
            raise ValueError('downloaded HAR does not match its frozen size/SHA-256')
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return target


if __name__ == '__main__':
    print(download(Path(__file__).resolve().parent))
