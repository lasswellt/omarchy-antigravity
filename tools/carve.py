#!/usr/bin/env python3
"""Carve an embedded FileDescriptorProto out of a Go binary.

Go's protobuf runtime stores each file's serialized FileDescriptorProto as a
plain byte slice in the data section. A FileDescriptorProto starts with field 1
(name), so the bytes `0x0a <len> <path>` mark the start. From there we walk the
protobuf wire format generically until we hit something that isn't a plausible
top-level field, and that's the end.
"""
import sys

MAX_FIELD = 32  # FileDescriptorProto tops out at 13; allow slack, reject garbage


def read_varint(buf, i):
    val = 0
    shift = 0
    while True:
        if i >= len(buf) or shift > 63:
            return None, i
        b = buf[i]
        i += 1
        val |= (b & 0x7F) << shift
        if not (b & 0x80):
            return val, i
        shift += 7


def find_end(buf, start):
    """Walk top-level fields from `start`; return offset just past the last valid one."""
    i = start
    end = start
    while i < len(buf):
        tag, j = read_varint(buf, i)
        if tag is None:
            break
        field, wire = tag >> 3, tag & 7
        if field == 0 or field > MAX_FIELD or wire in (3, 4, 6, 7):
            break
        if wire == 0:
            val, j = read_varint(buf, j)
            if val is None:
                break
        elif wire == 1:
            j += 8
        elif wire == 5:
            j += 4
        elif wire == 2:
            ln, j = read_varint(buf, j)
            if ln is None or j + ln > len(buf):
                break
            j += ln
        if j > len(buf):
            break
        i = end = j
    return end


def main():
    binary, path, out = sys.argv[1], sys.argv[2], sys.argv[3]
    data = open(binary, "rb").read()
    needle = bytes([0x0A, len(path)]) + path.encode()

    hits = []
    pos = data.find(needle)
    while pos != -1:
        hits.append(pos)
        pos = data.find(needle, pos + 1)

    if not hits:
        sys.exit(f"no descriptor start found for {path}")

    # Several copies can exist (one per Go package that links it); keep the longest.
    best = max(((h, find_end(data, h)) for h in hits), key=lambda p: p[1] - p[0])
    start, end = best
    blob = data[start:end]
    open(out, "wb").write(blob)
    print(f"{path}: {len(hits)} candidate(s), carved {len(blob)} bytes @ 0x{start:x} -> {out}")


if __name__ == "__main__":
    main()
