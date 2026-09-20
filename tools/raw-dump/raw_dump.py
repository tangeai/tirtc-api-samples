#!/usr/bin/env python3
"""Inspect, verify, extract, and convert TiRTC raw dump v1/v2 archives."""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import csv
import hashlib
import io
import json
import shutil
import stat
import struct
import sys
import wave
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any, BinaryIO, Iterable, Iterator


FORMAT = "tirtc.raw-dump"
VERSION = 1
SUPPORTED_VERSIONS = (1, 2)
INDEX_HEADER = (
    "capture_seq",
    "source_record_seq",
    "offset",
    "length",
    "source_timestamp",
    "source_timestamp_unit",
    "arrival_offset_us",
    "source_flags",
    "object_id",
    "download_attempt_id",
    "read_epoch",
    "object_record_offset",
)
RANGES_HEADER = (
    "response_id",
    "range_offset",
    "archive_offset",
    "length",
    "http_status",
    "result",
)
UPLINK_INDEX_HEADER = (
    "capture_seq",
    "offset",
    "length",
    "observation_offset_us",
    "source_timestamp",
    "source_timestamp_unit",
    "far_volume",
)
UPLINK_STAGES = ("captured", "render_reference", "processed", "encoded")
MAX_ARCHIVE_ENTRIES = 8192
MAX_ENTRY_BYTES = 1 << 30
MAX_TOTAL_BYTES = 2 << 30
MAX_JSON_BYTES = 16 << 20
MAX_INDEX_BYTES = 256 << 20
COPY_CHUNK_BYTES = 1 << 20
TSTR_MAX_HEADER_BYTES = 65536
TSTR_MAX_FRAME_BYTES = 8 << 20


class RawDumpError(RuntimeError):
    pass


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise RawDumpError(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def _load_json(payload: bytes, label: str) -> Any:
    if len(payload) > MAX_JSON_BYTES:
        raise RawDumpError(f"{label} exceeds {MAX_JSON_BYTES} bytes")
    try:
        return json.loads(payload.decode("utf-8"), object_pairs_hook=_strict_object)
    except UnicodeDecodeError as error:
        raise RawDumpError(f"{label} is not UTF-8: {error}") from error
    except json.JSONDecodeError as error:
        raise RawDumpError(f"{label} is not valid JSON: {error}") from error


def _decimal(value: Any, label: str, *, allow_empty: bool = False) -> int | None:
    if allow_empty and value == "":
        return None
    if not isinstance(value, str) or not value or not value.isascii() or not value.isdigit():
        raise RawDumpError(f"{label} must be an unsigned decimal string")
    parsed = int(value)
    if str(parsed) != value:
        raise RawDumpError(f"{label} must use canonical decimal notation")
    return parsed


def _signed_decimal(value: Any, label: str, *, allow_empty: bool = False) -> int | None:
    if allow_empty and value == "":
        return None
    if not isinstance(value, str) or not value or not value.isascii():
        raise RawDumpError(f"{label} must be a signed decimal string")
    digits = value[1:] if value.startswith("-") else value
    if not digits.isdigit() or (value.startswith("-") and digits == "0"):
        raise RawDumpError(f"{label} must be a signed decimal string")
    parsed = int(value)
    if str(parsed) != value:
        raise RawDumpError(f"{label} must use canonical decimal notation")
    return parsed


def _safe_member_name(name: str) -> str:
    if not name or "\\" in name or "\x00" in name:
        raise RawDumpError(f"unsafe ZIP entry name: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise RawDumpError(f"unsafe ZIP entry name: {name!r}")
    normalized = path.as_posix()
    if normalized != name.rstrip("/"):
        raise RawDumpError(f"non-canonical ZIP entry name: {name!r}")
    return normalized


def _is_zip_symlink(info: zipfile.ZipInfo) -> bool:
    mode = (info.external_attr >> 16) & 0xFFFF
    return stat.S_IFMT(mode) == stat.S_IFLNK


@dataclass(frozen=True)
class Entry:
    name: str
    size: int


class RawDumpArchive:
    def __init__(self, source: Path):
        self.source = source
        self._zip: zipfile.ZipFile | None = None
        self._entries: dict[str, Entry] = {}
        if source.is_dir():
            self._load_directory()
        else:
            self._load_zip()

    def __enter__(self) -> "RawDumpArchive":
        return self

    def __exit__(self, *_: object) -> None:
        if self._zip is not None:
            self._zip.close()

    def _load_directory(self) -> None:
        if self.source.is_symlink():
            raise RawDumpError("raw dump directory cannot be a symlink")
        total = 0
        for path in sorted(self.source.rglob("*")):
            if path.is_symlink():
                raise RawDumpError(f"raw dump contains a symlink: {path}")
            if not path.is_file():
                continue
            name = _safe_member_name(path.relative_to(self.source).as_posix())
            size = path.stat().st_size
            self._admit_entry(name, size)
            total += size
        if total > MAX_TOTAL_BYTES:
            raise RawDumpError(f"raw dump expands beyond {MAX_TOTAL_BYTES} bytes")
        self._validate_tree()

    def _load_zip(self) -> None:
        try:
            self._zip = zipfile.ZipFile(self.source)
        except (OSError, zipfile.BadZipFile) as error:
            raise RawDumpError(f"cannot open raw dump ZIP: {error}") from error
        infos = self._zip.infolist()
        if len(infos) > MAX_ARCHIVE_ENTRIES:
            raise RawDumpError(f"raw dump has more than {MAX_ARCHIVE_ENTRIES} entries")
        total = 0
        for info in infos:
            name = _safe_member_name(info.filename)
            if info.is_dir():
                continue
            if _is_zip_symlink(info):
                raise RawDumpError(f"raw dump contains a symlink entry: {name}")
            if info.compress_size < 0 or info.file_size < 0:
                raise RawDumpError(f"raw dump entry has an invalid size: {name}")
            self._admit_entry(name, info.file_size)
            total += info.file_size
        if total > MAX_TOTAL_BYTES:
            raise RawDumpError(f"raw dump expands beyond {MAX_TOTAL_BYTES} bytes")
        self._validate_tree()

    def _admit_entry(self, name: str, size: int) -> None:
        if name in self._entries:
            raise RawDumpError(f"raw dump has a duplicate entry: {name}")
        if size > MAX_ENTRY_BYTES:
            raise RawDumpError(f"raw dump entry exceeds {MAX_ENTRY_BYTES} bytes: {name}")
        self._entries[name] = Entry(name, size)
        if len(self._entries) > MAX_ARCHIVE_ENTRIES:
            raise RawDumpError(f"raw dump has more than {MAX_ARCHIVE_ENTRIES} files")

    def _validate_tree(self) -> None:
        names = sorted(self._entries)
        for index, name in enumerate(names[:-1]):
            if names[index + 1].startswith(name + "/"):
                raise RawDumpError(f"raw dump entry is both a file and directory: {name}")

    @property
    def entries(self) -> dict[str, Entry]:
        return dict(self._entries)

    def open(self, name: str) -> BinaryIO:
        name = _safe_member_name(name)
        if name not in self._entries:
            raise RawDumpError(f"raw dump entry is missing: {name}")
        if self._zip is not None:
            return self._zip.open(name)
        return (self.source / name).open("rb")

    def read(self, name: str, maximum: int) -> bytes:
        entry = self._entries.get(name)
        if entry is None:
            raise RawDumpError(f"raw dump entry is missing: {name}")
        if entry.size > maximum:
            raise RawDumpError(f"raw dump entry exceeds the read limit: {name}")
        with self.open(name) as handle:
            payload = handle.read(maximum + 1)
        if len(payload) != entry.size or len(payload) > maximum:
            raise RawDumpError(f"raw dump entry size changed while reading: {name}")
        return payload

    def copy_range(self, name: str, output: BinaryIO, offset: int, length: int) -> None:
        entry = self._entries.get(name)
        if entry is None or offset < 0 or length < 0 or offset + length > entry.size:
            raise RawDumpError(f"packet range exceeds entry: {name}@{offset}+{length}")
        with self.open(name) as source:
            remaining_offset = offset
            while remaining_offset:
                chunk = source.read(min(remaining_offset, COPY_CHUNK_BYTES))
                if not chunk:
                    raise RawDumpError(f"unexpected EOF while seeking in {name}")
                remaining_offset -= len(chunk)
            remaining = length
            while remaining:
                chunk = source.read(min(remaining, COPY_CHUNK_BYTES))
                if not chunk:
                    raise RawDumpError(f"unexpected EOF while reading {name}")
                output.write(chunk)
                remaining -= len(chunk)

    def sha256(self, name: str) -> str:
        digest = hashlib.sha256()
        with self.open(name) as handle:
            while True:
                chunk = handle.read(COPY_CHUNK_BYTES)
                if not chunk:
                    break
                digest.update(chunk)
        return digest.hexdigest()

    def extract_all(self, output_dir: Path) -> None:
        output_dir.mkdir(parents=True, exist_ok=True)
        root = output_dir.resolve()
        for name in sorted(self._entries):
            output = output_dir / PurePosixPath(name)
            output.parent.mkdir(parents=True, exist_ok=True)
            if root not in output.resolve().parents:
                raise RawDumpError(f"entry escapes output directory: {name}")
            with self.open(name) as source, output.open("wb") as target:
                shutil.copyfileobj(source, target, COPY_CHUNK_BYTES)


def _load_manifest(archive: RawDumpArchive) -> dict[str, Any]:
    manifest = _load_json(archive.read("manifest.json", MAX_JSON_BYTES), "manifest.json")
    if not isinstance(manifest, dict):
        raise RawDumpError("manifest.json must contain an object")
    if manifest.get("format") != FORMAT:
        raise RawDumpError(f"unsupported raw dump format: {manifest.get('format')!r}")
    if type(manifest.get("version")) is not int or manifest["version"] not in SUPPORTED_VERSIONS:
        raise RawDumpError(f"unsupported raw dump major version: {manifest.get('version')!r}")
    required = (
        "capture_id",
        "source_kind",
        "observation_point",
        "started_at_utc",
        "finished_at_utc",
        "duration_us",
        "runtime_version",
        "sdk_version",
        "nano_version",
        "identity_missing_reasons",
        "selected_sources",
        "stop_reason",
        "capture_complete",
        "empty",
        "counters",
        "limits",
        "streams",
        "objects",
        "files",
    )
    missing = [field for field in required if field not in manifest]
    if missing:
        raise RawDumpError(f"manifest is missing required fields: {', '.join(missing)}")
    for field in ("capture_id", "source_kind", "observation_point", "stop_reason"):
        if not isinstance(manifest.get(field), str) or not manifest[field]:
            raise RawDumpError(f"manifest field {field} must be a non-empty string")
    if manifest["source_kind"] not in ("rtc", "cloud_storage"):
        raise RawDumpError("manifest source_kind must be rtc or cloud_storage")
    if type(manifest.get("empty")) is not bool or type(manifest.get("capture_complete")) is not bool:
        raise RawDumpError("manifest empty and capture_complete must be booleans")
    if manifest["stop_reason"] not in (
        "user",
        "time_limit",
        "byte_limit",
        "source_closed",
        "resource_limit",
        "write_failed",
        "unknown",
    ):
        raise RawDumpError("manifest stop_reason is unknown to supported raw dump versions")
    _decimal(manifest["duration_us"], "manifest.duration_us")
    for field in ("started_at_utc", "finished_at_utc"):
        value = manifest[field]
        if value is not None:
            if not isinstance(value, str) or not value.endswith("Z"):
                raise RawDumpError(f"manifest.{field} must be a UTC timestamp or null")
            try:
                datetime.fromisoformat(value[:-1] + "+00:00")
            except ValueError as error:
                raise RawDumpError(f"manifest.{field} is invalid: {error}") from error
    for field in ("runtime_version", "sdk_version", "nano_version"):
        if manifest[field] is not None and not isinstance(manifest[field], str):
            raise RawDumpError(f"manifest.{field} must be a string or null")
    missing_reasons = manifest["identity_missing_reasons"]
    if not isinstance(missing_reasons, dict):
        raise RawDumpError("manifest.identity_missing_reasons must be an object")
    unknown_reasons = set(missing_reasons) - {"runtime_version", "sdk_version", "nano_version"}
    if unknown_reasons:
        raise RawDumpError("manifest.identity_missing_reasons contains an unknown field")
    for field in ("runtime_version", "sdk_version", "nano_version"):
        reason = missing_reasons.get(field)
        if manifest[field] is None and (not isinstance(reason, str) or not reason):
            raise RawDumpError(f"manifest.{field} is null without a missing reason")
        if reason is not None and (not isinstance(reason, str) or not reason):
            raise RawDumpError(f"manifest.identity_missing_reasons.{field} must be a non-empty string")
    if not isinstance(manifest["selected_sources"], list) or not manifest["selected_sources"]:
        raise RawDumpError("manifest selected_sources must be a non-empty array")
    selected: set[tuple[str, str, int]] = set()
    maximum_id = 15 if manifest["source_kind"] == "rtc" else 255
    uplink_selected = False
    for index, source in enumerate(manifest["selected_sources"]):
        if not isinstance(source, dict) or source.get("media_kind") not in ("audio", "video"):
            raise RawDumpError(f"manifest.selected_sources[{index}] has invalid media_kind")
        source_id = source.get("source_id")
        if type(source_id) is not int or not 0 <= source_id <= maximum_id:
            raise RawDumpError(f"manifest.selected_sources[{index}] has invalid source_id")
        direction = source.get("direction")
        if manifest["version"] == 2:
            if direction not in ("downlink", "uplink"):
                raise RawDumpError(f"manifest.selected_sources[{index}] has invalid direction")
            if direction == "uplink" and source["media_kind"] != "audio":
                raise RawDumpError(f"manifest.selected_sources[{index}] uplink must be audio")
            uplink_selected = uplink_selected or direction == "uplink"
        elif direction is not None:
            raise RawDumpError(f"manifest.selected_sources[{index}] v1 must not have direction")
        identity = (str(direction), source["media_kind"], source_id)
        if identity in selected:
            raise RawDumpError(f"manifest.selected_sources[{index}] is duplicated")
        selected.add(identity)
    if manifest["version"] == 2:
        if manifest["source_kind"] != "rtc" or not uplink_selected:
            raise RawDumpError("raw dump v2 requires RTC with at least one selected uplink audio source")
    for collection in ("streams", "objects", "files"):
        if not isinstance(manifest[collection], list):
            raise RawDumpError(f"manifest {collection} must be an array")
    if manifest["version"] == 2 and manifest["objects"]:
        raise RawDumpError("raw dump v2 RTC archive cannot contain cloud objects")
    counters = manifest["counters"]
    if not isinstance(counters, dict):
        raise RawDumpError("manifest counters must be an object")
    for field in (
        "observed_packets",
        "observed_bytes",
        "written_packets",
        "written_bytes",
        "unsaved_packets",
        "unsaved_bytes",
    ):
        if field not in counters:
            raise RawDumpError(f"manifest.counters is missing {field}")
        _decimal(counters[field], f"manifest.counters.{field}")
    if not isinstance(manifest["limits"], dict):
        raise RawDumpError("manifest limits must be an object")
    for field, value in manifest["limits"].items():
        _decimal(value, f"manifest.limits.{field}")
    return manifest


def _file_descriptors(value: Any, trail: str = "manifest") -> Iterator[tuple[str, dict[str, Any], str]]:
    if isinstance(value, dict):
        if "path" in value and ("sha256" in value or "length" in value or "size" in value):
            yield str(value["path"]), value, trail
        for key, child in value.items():
            if key not in ("path", "sha256", "length", "size"):
                yield from _file_descriptors(child, f"{trail}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _file_descriptors(child, f"{trail}[{index}]")


def _verify_descriptor(archive: RawDumpArchive, path: str, descriptor: dict[str, Any], trail: str) -> None:
    safe_path = _safe_member_name(path)
    entry = archive.entries.get(safe_path)
    if entry is None:
        raise RawDumpError(f"{trail} references missing entry: {safe_path}")
    length_value = descriptor.get("length", descriptor.get("size"))
    if length_value is not None:
        expected_length = _decimal(length_value, f"{trail}.length")
        if expected_length != entry.size:
            raise RawDumpError(
                f"{trail} length mismatch for {safe_path}: expected {expected_length}, got {entry.size}"
            )
    expected_sha = descriptor.get("sha256")
    if expected_sha is not None:
        if not isinstance(expected_sha, str) or len(expected_sha) != 64 or any(
            char not in "0123456789abcdef" for char in expected_sha
        ):
            raise RawDumpError(f"{trail}.sha256 must be 64 lowercase hex characters")
        actual_sha = archive.sha256(safe_path)
        if actual_sha != expected_sha:
            raise RawDumpError(
                f"{trail} SHA-256 mismatch for {safe_path}: expected {expected_sha}, got {actual_sha}"
            )


@dataclass(frozen=True)
class Packet:
    index_path: str
    data_path: str
    capture_seq: int
    source_record_seq: int | None
    offset: int
    length: int
    fields: dict[str, str]


def _stream_descriptors(manifest: dict[str, Any]) -> Iterator[tuple[dict[str, Any], str, str]]:
    selected = {
        (source.get("direction", "downlink"), source.get("media_kind"), source.get("source_id"))
        for source in manifest.get("selected_sources", [])
        if isinstance(source, dict)
    }
    seen_streams: set[tuple[str, str, int]] = set()
    for stream_index, stream in enumerate(manifest.get("streams", [])):
        if not isinstance(stream, dict):
            raise RawDumpError(f"manifest.streams[{stream_index}] must be an object")
        direction = stream.get("direction", "downlink" if manifest["version"] == 1 else None)
        media_kind = stream.get("media_kind")
        source_id = stream.get("source_id")
        if direction not in ("downlink", "uplink"):
            raise RawDumpError(f"manifest.streams[{stream_index}].direction is invalid")
        if media_kind not in ("audio", "video") or type(source_id) is not int:
            raise RawDumpError(f"manifest.streams[{stream_index}] has an invalid source identity")
        identity = (direction, media_kind, source_id)
        if identity not in selected:
            raise RawDumpError(f"manifest.streams[{stream_index}] was not selected")
        if identity in seen_streams:
            raise RawDumpError(f"manifest.streams[{stream_index}] duplicates a stream identity")
        seen_streams.add(identity)
        if direction == "uplink":
            if manifest["version"] != 2 or media_kind != "audio":
                raise RawDumpError(f"manifest.streams[{stream_index}] has invalid uplink media")
            yield from _uplink_stream_descriptors(stream, stream_index)
            continue
        segments = stream.get("segments")
        if segments is None:
            segments = [stream]
        if not isinstance(segments, list):
            raise RawDumpError(f"manifest.streams[{stream_index}].segments must be an array")
        for segment_index, segment in enumerate(segments):
            if not isinstance(segment, dict):
                raise RawDumpError("stream segment must be an object")
            trail = f"manifest.streams[{stream_index}].segments[{segment_index}]"
            codec = segment.get("codec")
            framing = segment.get("framing")
            if not isinstance(codec, str) or not codec:
                raise RawDumpError(f"{trail}.codec must be a non-empty string")
            if not isinstance(framing, str) or not framing:
                raise RawDumpError(f"{trail}.framing must be a non-empty string")
            for field in ("codec_provenance", "framing_provenance"):
                if segment.get(field) not in ("source_header", "bitstream_observed", "unknown"):
                    raise RawDumpError(f"{trail}.{field} has an invalid provenance")
            data = segment.get("data", segment.get("stream"))
            index = segment.get("index")
            if not isinstance(data, dict) or not isinstance(index, dict):
                raise RawDumpError(
                    f"manifest.streams[{stream_index}] segment {segment_index} needs data and index descriptors"
                )
            data_path = data.get("path")
            index_path = index.get("path")
            if not isinstance(data_path, str) or not isinstance(index_path, str):
                raise RawDumpError("stream data and index paths must be strings")
            merged = dict(stream)
            merged.update(segment)
            yield merged, _safe_member_name(data_path), _safe_member_name(index_path)


def _uplink_stream_descriptors(
    stream: dict[str, Any], stream_index: int
) -> Iterator[tuple[dict[str, Any], str, str]]:
    stages = stream.get("stages")
    if not isinstance(stages, list) or not stages:
        raise RawDumpError(f"manifest.streams[{stream_index}].stages must be a non-empty array")
    source_id = stream["source_id"]
    seen_stages: set[str] = set()
    for stage_index, stage_fact in enumerate(stages):
        trail = f"manifest.streams[{stream_index}].stages[{stage_index}]"
        if not isinstance(stage_fact, dict) or stage_fact.get("stage") not in UPLINK_STAGES:
            raise RawDumpError(f"{trail}.stage is invalid")
        stage = stage_fact["stage"]
        if stage in seen_stages:
            raise RawDumpError(f"{trail}.stage is duplicated")
        seen_stages.add(stage)
        segments = stage_fact.get("segments")
        if not isinstance(segments, list) or not segments:
            raise RawDumpError(f"{trail}.segments must be a non-empty array")
        expected_segment = 1
        for segment_index, segment in enumerate(segments):
            segment_trail = f"{trail}.segments[{segment_index}]"
            if not isinstance(segment, dict):
                raise RawDumpError(f"{segment_trail} must be an object")
            if segment.get("segment_id") != expected_segment:
                raise RawDumpError(f"{segment_trail}.segment_id must be {expected_segment}")
            expected_segment += 1
            for field in ("source_instance_id", "record_count", "byte_count"):
                _decimal(segment.get(field), f"{segment_trail}.{field}")
            format_fact = segment.get("format")
            if not isinstance(format_fact, dict):
                raise RawDumpError(f"{segment_trail}.format must be an object")
            if format_fact.get("encoding") != "s16le" or format_fact.get("bits_per_sample") != 16:
                raise RawDumpError(f"{segment_trail}.format must declare s16le 16-bit PCM")
            if type(format_fact.get("sample_rate_hz")) is not int or format_fact["sample_rate_hz"] <= 0:
                raise RawDumpError(f"{segment_trail}.format.sample_rate_hz must be positive")
            if type(format_fact.get("channels")) is not int or format_fact["channels"] <= 0:
                raise RawDumpError(f"{segment_trail}.format.channels must be positive")
            if stage == "encoded":
                for field in ("codec", "framing"):
                    if not isinstance(segment.get(field), str) or not segment[field]:
                        raise RawDumpError(f"{segment_trail}.{field} must be a non-empty string")
                for field in ("codec_provenance", "framing_provenance"):
                    if segment.get(field) not in ("source_header", "bitstream_observed", "unknown"):
                        raise RawDumpError(f"{segment_trail}.{field} has an invalid provenance")
                if "codec_config" not in segment:
                    raise RawDumpError(f"{segment_trail}.codec_config is required")
            data, index = segment.get("data"), segment.get("index")
            if not isinstance(data, dict) or not isinstance(index, dict):
                raise RawDumpError(f"{segment_trail} needs data and index descriptors")
            data_path, index_path = data.get("path"), index.get("path")
            if not isinstance(data_path, str) or not isinstance(index_path, str):
                raise RawDumpError(f"{segment_trail} data and index paths must be strings")
            file_stage = stage.replace("_", "-")
            suffix = "" if segment["segment_id"] == 1 else f".{segment['segment_id']:04d}"
            expected_stem = f"streams/uplink-audio-{source_id}/{file_stage}{suffix}"
            if index_path != expected_stem + ".index.csv":
                raise RawDumpError(f"{segment_trail}.index path does not match the v2 layout")
            if stage != "encoded" and data_path != expected_stem + ".pcm":
                raise RawDumpError(f"{segment_trail}.data path does not match the v2 PCM layout")
            if stage == "encoded":
                data_parent = PurePosixPath(data_path)
                wrong_parent = data_parent.parent.as_posix() != f"streams/uplink-audio-{source_id}"
                wrong_name = not data_parent.name.startswith(file_stage + suffix + ".")
                if wrong_parent or wrong_name or data_path == index_path or data_parent.name.endswith(
                    ".index.csv"
                ):
                    raise RawDumpError(f"{segment_trail}.data path does not match the v2 encoded layout")
            merged = dict(stream)
            merged.update(stage_fact)
            merged.update(segment)
            if stage != "encoded":
                merged.setdefault("codec", "pcm")
                merged.setdefault("framing", "s16le")
                merged.setdefault("codec_provenance", "source_header")
                merged.setdefault("framing_provenance", "source_header")
            yield merged, _safe_member_name(data_path), _safe_member_name(index_path)


def _packets(archive: RawDumpArchive, manifest: dict[str, Any]) -> Iterator[Packet]:
    seen_capture_seq: set[int] = set()
    for stream, data_path, index_path in _stream_descriptors(manifest):
        payload = archive.read(index_path, MAX_INDEX_BYTES)
        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError as error:
            raise RawDumpError(f"index is not UTF-8: {index_path}: {error}") from error
        if "\r" in text:
            raise RawDumpError(f"index must use LF line endings: {index_path}")
        reader = csv.DictReader(io.StringIO(text, newline=""))
        is_uplink = stream.get("direction") == "uplink"
        expected_header = UPLINK_INDEX_HEADER if is_uplink else INDEX_HEADER
        if tuple(reader.fieldnames or ()) != expected_header:
            raise RawDumpError(f"unexpected index header: {index_path}")
        expected_offset = 0
        previous_capture_seq = -1
        record_count = 0
        for line_number, row in enumerate(reader, start=2):
            if None in row or any(value is None for value in row.values()):
                raise RawDumpError(f"malformed CSV row: {index_path}:{line_number}")
            capture_seq = _decimal(row["capture_seq"], f"{index_path}:{line_number}.capture_seq")
            offset = _decimal(row["offset"], f"{index_path}:{line_number}.offset")
            length = _decimal(row["length"], f"{index_path}:{line_number}.length")
            if is_uplink:
                source_seq = None
                observation = _decimal(
                    row["observation_offset_us"],
                    f"{index_path}:{line_number}.observation_offset_us",
                )
                _signed_decimal(
                    row["source_timestamp"],
                    f"{index_path}:{line_number}.source_timestamp",
                )
                if row["source_timestamp_unit"] != "us":
                    raise RawDumpError(f"{index_path}:{line_number}.source_timestamp_unit must be us")
                far_volume = _decimal(
                    row["far_volume"],
                    f"{index_path}:{line_number}.far_volume",
                    allow_empty=True,
                )
                if stream["stage"] == "render_reference":
                    if far_volume is None or far_volume > 100:
                        raise RawDumpError(
                            f"{index_path}:{line_number}.far_volume must be in 0..100 for render_reference"
                        )
                elif far_volume is not None:
                    raise RawDumpError(
                        f"{index_path}:{line_number}.far_volume is only valid for render_reference"
                    )
                if observation is not None and observation >= 300_000_000:
                    raise RawDumpError(
                        f"observation exceeds the v2 capture window: {index_path}:{line_number}"
                    )
                if stream["stage"] != "encoded":
                    bytes_per_sample = stream["format"]["channels"] * 2
                    if length is not None and length % bytes_per_sample:
                        raise RawDumpError(
                            f"PCM record length is not sample-aligned: {index_path}:{line_number}"
                        )
            else:
                source_seq = _decimal(
                    row["source_record_seq"],
                    f"{index_path}:{line_number}.source_record_seq",
                    allow_empty=True,
                )
                arrival = _decimal(
                    row["arrival_offset_us"],
                    f"{index_path}:{line_number}.arrival_offset_us",
                    allow_empty=True,
                )
                _decimal(
                    row["source_timestamp"],
                    f"{index_path}:{line_number}.source_timestamp",
                    allow_empty=True,
                )
                _decimal(
                    row["source_flags"],
                    f"{index_path}:{line_number}.source_flags",
                    allow_empty=True,
                )
                _decimal(
                    row["object_record_offset"],
                    f"{index_path}:{line_number}.object_record_offset",
                    allow_empty=True,
                )
                if arrival is not None and arrival >= 300_000_000:
                    raise RawDumpError(f"arrival exceeds the v1 capture window: {index_path}:{line_number}")
            assert capture_seq is not None and offset is not None and length is not None
            if capture_seq <= previous_capture_seq:
                raise RawDumpError(f"capture_seq is not increasing in {index_path}:{line_number}")
            if capture_seq in seen_capture_seq:
                raise RawDumpError(f"duplicate capture_seq across indexes: {capture_seq}")
            if offset != expected_offset or length == 0:
                raise RawDumpError(f"index has a gap, overlap, or empty record: {index_path}:{line_number}")
            previous_capture_seq = capture_seq
            seen_capture_seq.add(capture_seq)
            expected_offset += length
            record_count += 1
            yield Packet(index_path, data_path, capture_seq, source_seq, offset, length, row)
        data_entry = archive.entries.get(data_path)
        if data_entry is None:
            raise RawDumpError(f"stream data is missing: {data_path}")
        if data_entry.size != expected_offset:
            raise RawDumpError(
                f"index coverage mismatch for {data_path}: indexed {expected_offset}, file {data_entry.size}"
            )
        if is_uplink:
            declared_records = _decimal(stream["record_count"], f"{index_path}.record_count")
            declared_bytes = _decimal(stream["byte_count"], f"{index_path}.byte_count")
            if declared_records != record_count or declared_bytes != expected_offset:
                raise RawDumpError(
                    f"uplink segment counts differ from index/data: {index_path}"
                )


def _read_csv(archive: RawDumpArchive, path: str, header: tuple[str, ...]) -> csv.DictReader:
    payload = archive.read(path, MAX_INDEX_BYTES)
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RawDumpError(f"CSV is not UTF-8: {path}: {error}") from error
    if "\r" in text:
        raise RawDumpError(f"CSV must use LF line endings: {path}")
    reader = csv.DictReader(io.StringIO(text, newline=""))
    if tuple(reader.fieldnames or ()) != header:
        raise RawDumpError(f"unexpected CSV header: {path}")
    return reader


def _verify_objects(archive: RawDumpArchive, manifest: dict[str, Any]) -> None:
    for object_index, object_fact in enumerate(manifest["objects"]):
        trail = f"manifest.objects[{object_index}]"
        if not isinstance(object_fact, dict):
            raise RawDumpError(f"{trail} must be an object")
        required = (
            "object_id",
            "download_attempt_id",
            "data",
            "ranges",
            "expected_size",
            "received_bytes",
            "complete",
            "acquired_before_capture",
            "result",
            "result_stage",
            "parse_result",
            "parse_stage",
            "expected_sha256",
            "actual_sha256",
        )
        missing = [field for field in required if field not in object_fact]
        if missing:
            raise RawDumpError(f"{trail} is missing required fields: {', '.join(missing)}")
        _decimal(object_fact["object_id"], f"{trail}.object_id")
        _decimal(object_fact["download_attempt_id"], f"{trail}.download_attempt_id")
        expected_size = _decimal(object_fact["expected_size"], f"{trail}.expected_size")
        received_bytes = _decimal(object_fact["received_bytes"], f"{trail}.received_bytes")
        assert expected_size is not None and received_bytes is not None
        if type(object_fact["complete"]) is not bool:
            raise RawDumpError(f"{trail}.complete must be a boolean")
        if type(object_fact["acquired_before_capture"]) is not bool:
            raise RawDumpError(f"{trail}.acquired_before_capture must be a boolean")
        for field in ("result", "parse_result"):
            if type(object_fact[field]) is not int:
                raise RawDumpError(f"{trail}.{field} must be an integer")
        for field in ("result_stage", "parse_stage"):
            if not isinstance(object_fact[field], str) or not object_fact[field]:
                raise RawDumpError(f"{trail}.{field} must be a non-empty string")

        data = object_fact["data"]
        ranges = object_fact["ranges"]
        if not isinstance(data, dict) or not isinstance(ranges, dict):
            raise RawDumpError(f"{trail}.data and ranges must be file descriptors")
        data_path = _safe_member_name(str(data.get("path", "")))
        ranges_path = _safe_member_name(str(ranges.get("path", "")))
        suffix = PurePosixPath(data_path).name
        expected_suffix = "object.tstr" if object_fact["complete"] else "object.part"
        if suffix != expected_suffix:
            raise RawDumpError(f"{trail}.data must name {expected_suffix}")

        reader = _read_csv(archive, ranges_path, RANGES_HEADER)
        byte_rows: dict[int, list[tuple[int, int, int]]] = {}
        response_rows: dict[int, tuple[int, int, str]] = {}
        final_row: tuple[int, str] | None = None
        next_archive_offset = 0
        for line_number, row in enumerate(reader, start=2):
            if None in row or any(value is None for value in row.values()):
                raise RawDumpError(f"malformed CSV row: {ranges_path}:{line_number}")
            response_id = _decimal(
                row["response_id"], f"{ranges_path}:{line_number}.response_id"
            )
            range_offset = _decimal(
                row["range_offset"], f"{ranges_path}:{line_number}.range_offset"
            )
            archive_offset = _decimal(
                row["archive_offset"],
                f"{ranges_path}:{line_number}.archive_offset",
                allow_empty=True,
            )
            length = _decimal(row["length"], f"{ranges_path}:{line_number}.length")
            http_status = _decimal(
                row["http_status"], f"{ranges_path}:{line_number}.http_status", allow_empty=True
            )
            assert response_id is not None and range_offset is not None and length is not None
            result = row["result"]
            if response_id == 0:
                if final_row is not None or range_offset != 0 or archive_offset is not None:
                    raise RawDumpError(f"invalid or duplicate final row: {ranges_path}:{line_number}")
                if http_status is not None or not (
                    result in ("complete", "partial") or result.startswith("error:")
                ):
                    raise RawDumpError(f"invalid final result: {ranges_path}:{line_number}")
                final_row = (length, result)
                continue
            if result == "bytes":
                if archive_offset is None or http_status is not None or length == 0:
                    raise RawDumpError(f"invalid byte row: {ranges_path}:{line_number}")
                if archive_offset != next_archive_offset:
                    raise RawDumpError(
                        f"object evidence has a gap or overlap: {ranges_path}:{line_number}"
                    )
                byte_rows.setdefault(response_id, []).append((range_offset, archive_offset, length))
                next_archive_offset += length
                continue
            if archive_offset is not None or result != "ok" and not result.startswith("error:"):
                raise RawDumpError(f"invalid response row: {ranges_path}:{line_number}")
            if response_id in response_rows:
                raise RawDumpError(f"duplicate response summary: {ranges_path}:{line_number}")
            if http_status is not None and not 100 <= http_status <= 599:
                raise RawDumpError(f"invalid HTTP status: {ranges_path}:{line_number}")
            response_rows[response_id] = (range_offset, length, result)

        if final_row is None:
            raise RawDumpError(f"ranges CSV has no final row: {ranges_path}")
        if final_row[0] != received_bytes or next_archive_offset != received_bytes:
            raise RawDumpError(f"{trail}.received_bytes does not match ranges evidence")
        if set(byte_rows) - set(response_rows):
            raise RawDumpError(f"ranges CSV has bytes without a response summary: {ranges_path}")
        for response_id, rows in byte_rows.items():
            response_offset, response_length, _ = response_rows[response_id]
            ordered = sorted(rows)
            cursor = response_offset
            for original_offset, _, row_length in ordered:
                if original_offset != cursor:
                    raise RawDumpError(f"response byte rows are not contiguous: {ranges_path}")
                cursor += row_length
            if cursor != response_offset + response_length:
                raise RawDumpError(f"response byte count does not match its summary: {ranges_path}")
        for response_id, (_, response_length, _) in response_rows.items():
            actual = sum(row[2] for row in byte_rows.get(response_id, []))
            if actual != response_length:
                raise RawDumpError(f"response {response_id} byte count mismatch: {ranges_path}")

        if object_fact["complete"]:
            if final_row[1] != "complete":
                raise RawDumpError(f"complete object lacks a complete final row: {ranges_path}")
            successful = sorted(
                (offset, offset + length)
                for offset, length, result in response_rows.values()
                if result == "ok"
            )
            covered = 0
            for begin, end in successful:
                if end > expected_size or begin > covered:
                    raise RawDumpError(f"complete object response coverage is invalid: {ranges_path}")
                covered = max(covered, end)
            if covered != expected_size:
                raise RawDumpError(f"complete object response coverage has holes: {ranges_path}")
            data_entry = archive.entries[data_path]
            if data_entry.size != expected_size:
                raise RawDumpError(f"complete object size differs from expected_size: {data_path}")
            expected_sha = object_fact["expected_sha256"]
            actual_sha = object_fact["actual_sha256"]
            descriptor_sha = data.get("sha256")
            if expected_sha is not None and expected_sha != descriptor_sha:
                raise RawDumpError(f"complete object differs from its expected SHA-256: {data_path}")
            if actual_sha != descriptor_sha:
                raise RawDumpError(f"complete object actual SHA-256 is inconsistent: {data_path}")
        else:
            if final_row[1] == "complete":
                raise RawDumpError(f"partial object has a complete final row: {ranges_path}")
            if archive.entries[data_path].size != received_bytes:
                raise RawDumpError(f"partial object size differs from received_bytes: {data_path}")


def verify_archive(archive: RawDumpArchive) -> tuple[dict[str, Any], list[Packet]]:
    manifest = _load_manifest(archive)
    descriptors = list(_file_descriptors(manifest))
    seen_descriptor_paths: set[str] = set()
    for path, descriptor, trail in descriptors:
        if not isinstance(path, str):
            raise RawDumpError(f"{trail}.path must be a string")
        safe_path = _safe_member_name(path)
        _verify_descriptor(archive, safe_path, descriptor, trail)
        seen_descriptor_paths.add(safe_path)
    packets = list(_packets(archive, manifest))
    _verify_objects(archive, manifest)
    counters = manifest["counters"]
    written_packets = _decimal(counters["written_packets"], "manifest.counters.written_packets")
    written_bytes = _decimal(counters["written_bytes"], "manifest.counters.written_bytes")
    if written_packets != len(packets):
        raise RawDumpError(
            f"written packet count mismatch: manifest {written_packets}, indexes {len(packets)}"
        )
    if written_bytes != sum(packet.length for packet in packets):
        raise RawDumpError("written byte count differs from indexed data")
    if manifest["empty"] != (written_packets == 0):
        raise RawDumpError("manifest empty does not match written packet count")
    unsaved_packets = _decimal(counters["unsaved_packets"], "manifest.counters.unsaved_packets")
    unsaved_bytes = _decimal(counters["unsaved_bytes"], "manifest.counters.unsaved_bytes")
    if manifest["capture_complete"] and (unsaved_packets != 0 or unsaved_bytes != 0):
        raise RawDumpError("capture_complete cannot report unsaved data")
    expected_files = {"manifest.json"} | seen_descriptor_paths
    undeclared = set(archive.entries) - expected_files
    if undeclared:
        raise RawDumpError(f"raw dump contains undeclared files: {', '.join(sorted(undeclared))}")
    return manifest, packets


def _summary(manifest: dict[str, Any], packets: Iterable[Packet]) -> dict[str, Any]:
    packet_list = list(packets)
    summary = {
        "format": manifest["format"],
        "version": manifest["version"],
        "capture_id": manifest["capture_id"],
        "source_kind": manifest["source_kind"],
        "stop_reason": manifest["stop_reason"],
        "capture_complete": manifest["capture_complete"],
        "empty": manifest["empty"],
        "packet_count": len(packet_list),
        "stream_count": len(manifest.get("streams", [])),
        "object_count": len(manifest.get("objects", [])),
    }
    if manifest["version"] == 2:
        streams = {
            (stream.get("direction"), stream.get("media_kind"), stream.get("source_id")): stream
            for stream in manifest.get("streams", [])
            if isinstance(stream, dict)
        }
        summary["uplink_audio"] = []
        for selected in manifest["selected_sources"]:
            if selected.get("direction") != "uplink":
                continue
            stream = streams.get(("uplink", "audio", selected["source_id"]), {})
            observed = [
                stage.get("stage")
                for stage in stream.get("stages", [])
                if isinstance(stage, dict) and stage.get("stage") in UPLINK_STAGES
            ]
            summary["uplink_audio"].append(
                {
                    "stream": f"uplink-audio-{selected['source_id']}",
                    "observed_stages": observed,
                    "unobserved_stages": [stage for stage in UPLINK_STAGES if stage not in observed],
                    "stages": [
                        {
                            "stage": stage["stage"],
                            "segment_count": len(stage["segments"]),
                            "record_count": str(
                                sum(int(segment["record_count"]) for segment in stage["segments"])
                            ),
                            "byte_count": str(
                                sum(int(segment["byte_count"]) for segment in stage["segments"])
                            ),
                            "formats": [segment["format"] for segment in stage["segments"]],
                            "codecs": [
                                segment["codec"]
                                for segment in stage["segments"]
                                if "codec" in segment
                            ],
                        }
                        for stage in stream.get("stages", [])
                    ],
                }
            )
    return summary


def _select_packet(packets: Iterable[Packet], capture_seq: int) -> Packet:
    matches = [packet for packet in packets if packet.capture_seq == capture_seq]
    if len(matches) != 1:
        raise RawDumpError(f"capture_seq {capture_seq} matched {len(matches)} packets")
    return matches[0]


def _stream_identity(stream: dict[str, Any], data_path: str) -> str:
    explicit = stream.get("stream_id", stream.get("id"))
    if isinstance(explicit, str) and explicit:
        return explicit
    media_kind = stream.get("media_kind")
    source_id = stream.get("source_id")
    if isinstance(media_kind, str) and isinstance(source_id, int):
        if stream.get("direction") == "uplink":
            return f"uplink-{media_kind}-{source_id}"
        return f"{media_kind}-{source_id}"
    parts = PurePosixPath(data_path).parts
    return parts[1] if len(parts) > 2 and parts[0] == "streams" else data_path


def _select_stream(
    manifest: dict[str, Any], stream_name: str, segment_id: str | None, stage: str | None = None
) -> tuple[dict[str, Any], str, str]:
    matches: list[tuple[dict[str, Any], str, str]] = []
    for stream, data_path, index_path in _stream_descriptors(manifest):
        identity = _stream_identity(stream, data_path)
        actual_segment = str(stream.get("segment_id", ""))
        if (
            stream_name in (identity, data_path)
            and (segment_id is None or segment_id == actual_segment)
            and (stage is None or stream.get("stage") == stage)
        ):
            matches.append((stream, data_path, index_path))
    if len(matches) != 1:
        raise RawDumpError(f"stream selection matched {len(matches)} segments")
    return matches[0]


def _write_wave(
    archive: RawDumpArchive, data_path: str, stream: dict[str, Any], output_path: Path
) -> None:
    format_fact = stream.get("format")
    if not isinstance(format_fact, dict) or format_fact.get("encoding") != "s16le":
        raise RawDumpError("PCM conversion requires a declared s16le format")
    with wave.open(str(output_path), "wb") as output:
        output.setnchannels(format_fact["channels"])
        output.setsampwidth(2)
        output.setframerate(format_fact["sample_rate_hz"])
        with archive.open(data_path) as source:
            while True:
                chunk = source.read(COPY_CHUNK_BYTES)
                if not chunk:
                    break
                output.writeframesraw(chunk)


def _aac_config_bytes(archive: RawDumpArchive, stream: dict[str, Any], args: argparse.Namespace) -> tuple[bytes, str]:
    if args.aac_config_hex:
        try:
            return bytes.fromhex(args.aac_config_hex), "explicit_hex"
        except ValueError as error:
            raise RawDumpError(f"invalid --aac-config-hex: {error}") from error
    if args.aac_config_file:
        return args.aac_config_file.read_bytes(), "explicit_file"
    descriptor = stream.get("codec_config")
    if isinstance(descriptor, dict) and descriptor.get("provenance") in (
        "source_header",
        "bitstream_observed",
    ):
        path = descriptor.get("path")
        if isinstance(path, str):
            return archive.read(path, 4096), str(descriptor["provenance"])
    raise RawDumpError("raw AAC conversion needs captured source config or explicit config")


def _parse_audio_specific_config(config: bytes) -> tuple[int, int, int]:
    if len(config) < 2:
        raise RawDumpError("AAC AudioSpecificConfig is too short")
    bits = int.from_bytes(config[:2], "big")
    object_type = (bits >> 11) & 0x1F
    frequency_index = (bits >> 7) & 0x0F
    channel_config = (bits >> 3) & 0x0F
    if object_type != 2 or frequency_index == 15 or channel_config == 0:
        raise RawDumpError("only explicit AAC-LC AudioSpecificConfig is supported")
    return object_type, frequency_index, channel_config


def _adts_header(payload_bytes: int, config: tuple[int, int, int]) -> bytes:
    object_type, frequency_index, channel_config = config
    frame_length = payload_bytes + 7
    if frame_length > 0x1FFF:
        raise RawDumpError("AAC access unit is too large for ADTS")
    profile = object_type - 1
    return bytes(
        (
            0xFF,
            0xF1,
            (profile << 6) | (frequency_index << 2) | (channel_config >> 2),
            ((channel_config & 3) << 6) | (frame_length >> 11),
            (frame_length >> 3) & 0xFF,
            ((frame_length & 7) << 5) | 0x1F,
            0xFC,
        )
    )


def _convert(args: argparse.Namespace) -> None:
    with RawDumpArchive(args.archive) as archive:
        manifest, packets = verify_archive(archive)
        stream, data_path, index_path = _select_stream(
            manifest, args.stream, args.segment, args.stage
        )
        selected = [packet for packet in packets if packet.index_path == index_path]
        codec = str(stream.get("codec", "unknown")).lower()
        framing = str(stream.get("framing", "unknown")).lower()
        if codec == "pcm" and framing == "s16le":
            conversion = "pcm_s16le_to_wav"
        elif codec == "aac" and framing in ("raw", "raw_access_unit", "aac_raw_access_unit"):
            conversion = "aac_raw"
        elif codec == "aac" and framing == "adts":
            conversion = "copy"
        elif codec in ("h264", "h265") and framing == "annex_b":
            conversion = "copy"
        else:
            raise RawDumpError(
                f"conversion is unsupported for codec {codec!r} with framing {framing!r}"
            )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        config_source: str | None = None
        if conversion == "pcm_s16le_to_wav":
            _write_wave(archive, data_path, stream, args.output)
        else:
            with args.output.open("wb") as output:
                if conversion == "aac_raw":
                    config_bytes, config_source = _aac_config_bytes(archive, stream, args)
                    config = _parse_audio_specific_config(config_bytes)
                    for packet in selected:
                        output.write(_adts_header(packet.length, config))
                        archive.copy_range(data_path, output, packet.offset, packet.length)
                else:
                    with archive.open(data_path) as source:
                        shutil.copyfileobj(source, output, COPY_CHUNK_BYTES)
        report_path = args.report or args.output.with_suffix(args.output.suffix + ".report.json")
        output_digest = hashlib.sha256()
        with args.output.open("rb") as converted:
            while True:
                chunk = converted.read(COPY_CHUNK_BYTES)
                if not chunk:
                    break
                output_digest.update(chunk)
        report = {
            "format": "tirtc.raw-dump-conversion",
            "version": 1,
            "archive_version": manifest["version"],
            "capture_id": manifest["capture_id"],
            "source_path": data_path,
            "source_sha256": archive.sha256(data_path),
            "codec": codec,
            "source_framing": framing,
            "output_path": str(args.output),
            "output_size": str(args.output.stat().st_size),
            "output_sha256": output_digest.hexdigest(),
            "codec_config_source": config_source,
            "stage": stream.get("stage"),
            "conversion": conversion,
            "source_format": stream.get("format"),
        }
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(report, sort_keys=True))


def _read_secret_key(args: argparse.Namespace) -> bytes:
    if args.key_file is not None:
        payload = args.key_file.read_bytes()
    elif args.key_stdin:
        payload = sys.stdin.buffer.read(4097)
    else:
        raise RawDumpError("provide --key-file or --key-stdin")
    if len(payload) == 16:
        return payload
    encoded = payload.strip()
    if len(encoded) == 32:
        try:
            payload = bytes.fromhex(encoded.decode("ascii"))
        except (UnicodeDecodeError, ValueError):
            pass
    if len(payload) != 16:
        raise RawDumpError("TSTR key must contain 16 raw bytes or 32 hexadecimal characters")
    return payload


def _decrypt_aes_cbc(ciphertext: bytes, key: bytes, iv: bytes) -> bytes:
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    except ImportError as error:
        crypto_path = ctypes.util.find_library("crypto")
        if not crypto_path:
            raise RawDumpError(
                "TSTR decryption requires OpenSSL libcrypto or the optional 'cryptography' package"
            ) from error
        try:
            crypto = ctypes.CDLL(crypto_path)
            crypto.EVP_CIPHER_CTX_new.restype = ctypes.c_void_p
            crypto.EVP_CIPHER_CTX_free.argtypes = [ctypes.c_void_p]
            crypto.EVP_aes_128_cbc.restype = ctypes.c_void_p
            crypto.EVP_DecryptInit_ex.argtypes = [
                ctypes.c_void_p,
                ctypes.c_void_p,
                ctypes.c_void_p,
                ctypes.c_void_p,
                ctypes.c_void_p,
            ]
            crypto.EVP_DecryptUpdate.argtypes = [
                ctypes.c_void_p,
                ctypes.c_void_p,
                ctypes.POINTER(ctypes.c_int),
                ctypes.c_void_p,
                ctypes.c_int,
            ]
            crypto.EVP_DecryptFinal_ex.argtypes = [
                ctypes.c_void_p,
                ctypes.c_void_p,
                ctypes.POINTER(ctypes.c_int),
            ]
            context = crypto.EVP_CIPHER_CTX_new()
            if not context:
                raise RawDumpError("OpenSSL could not allocate a decryption context")
            key_buffer = ctypes.create_string_buffer(key)
            iv_buffer = ctypes.create_string_buffer(iv)
            input_buffer = ctypes.create_string_buffer(ciphertext)
            output_buffer = ctypes.create_string_buffer(len(ciphertext) + 16)
            produced = ctypes.c_int()
            final_bytes = ctypes.c_int()
            try:
                ok = crypto.EVP_DecryptInit_ex(
                    context,
                    crypto.EVP_aes_128_cbc(),
                    None,
                    key_buffer,
                    iv_buffer,
                )
                ok = ok and crypto.EVP_DecryptUpdate(
                    context,
                    output_buffer,
                    ctypes.byref(produced),
                    input_buffer,
                    len(ciphertext),
                )
                final_pointer = ctypes.byref(output_buffer, produced.value)
                ok = ok and crypto.EVP_DecryptFinal_ex(
                    context, final_pointer, ctypes.byref(final_bytes)
                )
                if not ok:
                    raise RawDumpError("OpenSSL rejected the TSTR frame ciphertext or padding")
                return output_buffer.raw[: produced.value + final_bytes.value]
            finally:
                crypto.EVP_CIPHER_CTX_free(context)
        except (AttributeError, OSError) as library_error:
            raise RawDumpError(f"OpenSSL libcrypto is unavailable: {library_error}") from library_error
    decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    padded = decryptor.update(ciphertext) + decryptor.finalize()
    if not padded:
        raise RawDumpError("TSTR frame decrypted to an empty payload")
    padding = padded[-1]
    if padding == 0 or padding > 16 or padded[-padding:] != bytes([padding]) * padding:
        raise RawDumpError("TSTR frame has invalid PKCS#7 padding")
    return padded[:-padding]


def _inspect_tstr(args: argparse.Namespace) -> None:
    key = _read_secret_key(args)
    if args.archive is not None:
        if not args.object_path:
            raise RawDumpError("--object-path is required with --archive")
        with RawDumpArchive(args.archive) as archive:
            payload = archive.read(args.object_path, MAX_ENTRY_BYTES)
    else:
        if args.input is None:
            raise RawDumpError("provide --input or --archive with --object-path")
        if args.input.stat().st_size > MAX_ENTRY_BYTES:
            raise RawDumpError("TSTR input exceeds the file limit")
        payload = args.input.read_bytes()
    if len(payload) < 28 or payload[:4] != b"TSTR" or struct.unpack_from(">H", payload, 4)[0] != 1:
        raise RawDumpError("unsupported TSTR header identity")
    header_size = struct.unpack_from(">I", payload, 6)[0]
    if not 28 <= header_size <= min(TSTR_MAX_HEADER_BYTES, len(payload)):
        raise RawDumpError("invalid TSTR header size")
    if payload[10] != 1 or payload[11] != 16:
        raise RawDumpError("unsupported TSTR encryption declaration")
    iv = payload[12:28]
    extension_offset = 28
    while extension_offset < header_size:
        if header_size - extension_offset < 2:
            raise RawDumpError("truncated TSTR extension header")
        extension_type = payload[extension_offset]
        extension_size = payload[extension_offset + 1]
        extension_offset += 2
        if extension_type == 0:
            if extension_size != 0 or extension_offset != header_size:
                raise RawDumpError("invalid TSTR extension terminator")
            break
        if extension_size > header_size - extension_offset:
            raise RawDumpError("invalid TSTR extension size")
        extension_offset += extension_size
    frames: list[dict[str, Any]] = []
    offset = header_size
    while offset < len(payload):
        record_offset = offset
        if len(payload) - offset < 16:
            raise RawDumpError("truncated TSTR frame header")
        channel_id, media, flags, frame_version = payload[offset : offset + 4]
        timestamp_ms = struct.unpack_from(">Q", payload, offset + 4)[0]
        ciphertext_size = struct.unpack_from(">I", payload, offset + 12)[0]
        offset += 16
        if (
            frame_version != 1
            or ciphertext_size == 0
            or ciphertext_size % 16
            or ciphertext_size > TSTR_MAX_FRAME_BYTES
            or ciphertext_size > len(payload) - offset
        ):
            raise RawDumpError(f"invalid TSTR frame at offset {record_offset}")
        plaintext = _decrypt_aes_cbc(payload[offset : offset + ciphertext_size], key, iv)
        frames.append(
            {
                "record_offset": str(record_offset),
                "channel_id": channel_id,
                "media": media,
                "flags": flags,
                "timestamp_ms": str(timestamp_ms),
                "payload_length": str(len(plaintext)),
                "payload_sha256": hashlib.sha256(plaintext).hexdigest(),
            }
        )
        offset += ciphertext_size
    if not frames:
        raise RawDumpError("TSTR object has no frames")
    print(
        json.dumps(
            {
                "format": "tirtc.tstr-inspection",
                "version": 1,
                "object_sha256": hashlib.sha256(payload).hexdigest(),
                "frame_count": len(frames),
                "frames": frames,
            },
            indent=2,
            sort_keys=True,
        )
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser("inspect", help="print a bounded archive summary")
    inspect_parser.add_argument("archive", type=Path)

    verify_parser = subparsers.add_parser("verify", help="verify structure, hashes, and indexes")
    verify_parser.add_argument("archive", type=Path)

    extract_parser = subparsers.add_parser("extract-packet", help="extract one original packet")
    extract_parser.add_argument("archive", type=Path)
    extract_parser.add_argument("--capture-seq", type=int, required=True)
    extract_parser.add_argument("--output", type=Path, required=True)

    unpack_parser = subparsers.add_parser("unpack", help="safely unpack a verified archive")
    unpack_parser.add_argument("archive", type=Path)
    unpack_parser.add_argument("output", type=Path)

    convert_parser = subparsers.add_parser("convert", help="create a separate playable stream")
    convert_parser.add_argument("archive", type=Path)
    convert_parser.add_argument("--stream", required=True)
    convert_parser.add_argument("--segment")
    convert_parser.add_argument("--stage", choices=UPLINK_STAGES)
    convert_parser.add_argument("--output", type=Path, required=True)
    convert_parser.add_argument("--report", type=Path)
    convert_parser.add_argument("--aac-config-hex")
    convert_parser.add_argument("--aac-config-file", type=Path)

    tstr_parser = subparsers.add_parser(
        "inspect-tstr", help="decrypt and inspect a TSTR object without exposing key material"
    )
    source = tstr_parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--input", type=Path)
    source.add_argument("--archive", type=Path)
    tstr_parser.add_argument("--object-path")
    key = tstr_parser.add_mutually_exclusive_group(required=True)
    key.add_argument("--key-file", type=Path)
    key.add_argument("--key-stdin", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command in ("inspect", "verify", "extract-packet", "unpack"):
            with RawDumpArchive(args.archive) as archive:
                manifest, packets = verify_archive(archive)
                if args.command == "inspect":
                    print(json.dumps(_summary(manifest, packets), indent=2, sort_keys=True))
                elif args.command == "verify":
                    print(json.dumps({"status": "ok", **_summary(manifest, packets)}, sort_keys=True))
                elif args.command == "extract-packet":
                    packet = _select_packet(packets, args.capture_seq)
                    args.output.parent.mkdir(parents=True, exist_ok=True)
                    with args.output.open("wb") as output:
                        archive.copy_range(packet.data_path, output, packet.offset, packet.length)
                    print(
                        json.dumps(
                            {
                                "status": "ok",
                                "capture_seq": str(packet.capture_seq),
                                "output": str(args.output),
                                "length": str(packet.length),
                                "sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
                            },
                            sort_keys=True,
                        )
                    )
                else:
                    if args.output.is_symlink():
                        raise RawDumpError("unpack output directory cannot be a symlink")
                    if args.output.exists() and any(args.output.iterdir()):
                        raise RawDumpError("unpack output directory must be empty")
                    archive.extract_all(args.output)
                    print(args.output)
        elif args.command == "convert":
            _convert(args)
        elif args.command == "inspect-tstr":
            _inspect_tstr(args)
        else:
            raise RawDumpError(f"unsupported command: {args.command}")
    except (OSError, RawDumpError, zipfile.BadZipFile) as error:
        print(f"raw-dump: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
