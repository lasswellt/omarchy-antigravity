#!/usr/bin/env python3
"""Turn `protoc --decode=FileDescriptorProto` text back into readable .proto-ish source.

Only tracks what we care about: messages, their fields, enums, oneofs, services.
Option blobs and other noise are dropped.
"""
import re
import sys

TYPE = {
    "TYPE_STRING": "string", "TYPE_INT32": "int32", "TYPE_INT64": "int64",
    "TYPE_UINT32": "uint32", "TYPE_UINT64": "uint64", "TYPE_BOOL": "bool",
    "TYPE_DOUBLE": "double", "TYPE_FLOAT": "float", "TYPE_BYTES": "bytes",
    "TYPE_MESSAGE": "", "TYPE_ENUM": "", "TYPE_SINT32": "sint32",
    "TYPE_SINT64": "sint64", "TYPE_FIXED32": "fixed32", "TYPE_FIXED64": "fixed64",
}


def main():
    lines = sys.stdin.read().split("\n")
    # Stack of (kind, indent) so we know which block a scalar belongs to.
    stack = []
    cur = {}
    out = []
    depth = 0

    def flush_field():
        if not cur.get("name"):
            return
        t = TYPE.get(cur.get("type", ""), "")
        if not t:
            t = cur.get("type_name", "?").split(".")[-1]
        label = "repeated " if cur.get("label") == "LABEL_REPEATED" else ""
        oneof = f"  // oneof #{cur['oneof_index']}" if "oneof_index" in cur else ""
        out.append(f"{'  ' * depth}  {label}{t} {cur['name']} = {cur.get('number','?')};{oneof}")

    for raw in lines:
        s = raw.strip()
        if not s:
            continue
        m = re.match(r"^(\w+) \{$", s)
        if m:
            kind = m.group(1)
            if kind in ("message_type", "nested_type", "enum_type", "service"):
                stack.append((kind, None))
                cur = {"_block": kind}
            elif kind == "field":
                cur = {"_block": "field"}
            elif kind in ("value", "method", "oneof_decl"):
                cur = {"_block": kind}
            else:
                stack.append(("skip", None))
            continue
        if s == "}":
            if cur.get("_block") == "field":
                flush_field()
                cur = {}
                continue
            if cur.get("_block") == "value":
                out.append(f"{'  ' * depth}  {cur.get('name','?')} = {cur.get('number','?')};")
                cur = {}
                continue
            if cur.get("_block") == "oneof_decl":
                out.append(f"{'  ' * depth}  // oneof {cur.get('name','?')}")
                cur = {}
                continue
            if cur.get("_block") == "method":
                out.append(f"{'  ' * depth}  rpc {cur.get('name','?')}({cur.get('input_type','?').split('.')[-1]})"
                           f" returns ({cur.get('output_type','?').split('.')[-1]});")
                cur = {}
                continue
            if stack:
                kind, _ = stack.pop()
                if kind != "skip":
                    out.append(f"{'  ' * (depth - 1)}}}\n")
                    depth -= 1
            continue
        m = re.match(r'^(\w+): "?([^"]*)"?$', s)
        if m:
            k, v = m.group(1), m.group(2)
            if k == "name" and cur.get("_block") in ("message_type", "nested_type", "enum_type", "service"):
                word = {"message_type": "message", "nested_type": "message",
                        "enum_type": "enum", "service": "service"}[cur["_block"]]
                out.append(f"{'  ' * depth}{word} {v} {{")
                depth += 1
                cur = {}
            else:
                cur[k] = v
    print("\n".join(out))


if __name__ == "__main__":
    main()
