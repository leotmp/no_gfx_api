#!/usr/bin/env python3
"""
Deep MISL LSP integration tests over stdio.

Spawns misl_lsp.exe, speaks LSP framing, types character-by-character where useful,
and asserts completion / hover / definition / diagnostics / codeLens / SPIR-V preview.

Usage (from repo root):
  python oge/misl/tools/misl_lsp/harness/lsp_deep_test.py
  python oge/misl/tools/misl_lsp/harness/lsp_deep_test.py --exe ./misl_lsp.exe
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional


REPO = Path(__file__).resolve().parents[5]  # survivor/


def fmag_instr_contains(text: str, needle: str) -> bool:
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith(";"):
            continue
        if needle in s:
            return True
    return False


@dataclass
class Fail:
    name: str
    detail: str


@dataclass
class Client:
    proc: subprocess.Popen
    server_capabilities: dict = field(default_factory=dict)
    _id: int = 0
    _pending: dict[int, dict] = field(default_factory=dict)
    _notifs: list[dict] = field(default_factory=list)
    _lock: threading.Lock = field(default_factory=threading.Lock)
    _reader_done: bool = False

    def start_reader(self) -> None:
        t = threading.Thread(target=self._read_loop, daemon=True)
        t.start()

    def _read_loop(self) -> None:
        try:
            while True:
                msg = self._read_one()
                if msg is None:
                    break
                with self._lock:
                    if "id" in msg and ("result" in msg or "error" in msg):
                        self._pending[msg["id"]] = msg
                    else:
                        self._notifs.append(msg)
        finally:
            self._reader_done = True

    def _read_one(self) -> Optional[dict]:
        headers: dict[str, str] = {}
        while True:
            line = self.proc.stdout.readline()
            if not line:
                return None
            if line in (b"\r\n", b"\n"):
                break
            if b":" in line:
                k, v = line.decode("utf-8", errors="replace").split(":", 1)
                headers[k.strip().lower()] = v.strip()
        n = int(headers.get("content-length", "0"))
        if n <= 0:
            return None
        body = b""
        while len(body) < n:
            chunk = self.proc.stdout.read(n - len(body))
            if not chunk:
                return None
            body += chunk
        return json.loads(body.decode("utf-8"))

    def _write(self, obj: dict) -> None:
        data = json.dumps(obj, separators=(",", ":")).encode("utf-8")
        header = f"Content-Length: {len(data)}\r\n\r\n".encode("ascii")
        self.proc.stdin.write(header + data)
        self.proc.stdin.flush()

    def request(self, method: str, params: Any, timeout: float = 8.0) -> dict:
        self._id += 1
        rid = self._id
        self._write({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self._lock:
                if rid in self._pending:
                    msg = self._pending.pop(rid)
                    if "error" in msg and msg["error"]:
                        raise RuntimeError(f"{method} error: {msg['error']}")
                    return msg.get("result")
            if self.proc.poll() is not None:
                raise RuntimeError(f"LSP exited while waiting for {method} (code {self.proc.returncode})")
            time.sleep(0.01)
        raise TimeoutError(f"timeout waiting for {method} id={rid}")

    def notify(self, method: str, params: Any) -> None:
        self._write({"jsonrpc": "2.0", "method": method, "params": params})

    def drain_diags(self) -> list[dict]:
        with self._lock:
            out = [n for n in self._notifs if n.get("method") == "textDocument/publishDiagnostics"]
            self._notifs = [n for n in self._notifs if n.get("method") != "textDocument/publishDiagnostics"]
            return out

    def close(self) -> None:
        try:
            self.request("shutdown", None, timeout=3.0)
            self.notify("exit", None)
        except Exception:
            pass
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()


def path_uri(p: Path) -> str:
    return p.resolve().as_uri()


def pos_at(text: str, needle: str, after: bool = True) -> dict:
    """Return LSP Position at (or after) the first occurrence of needle."""
    idx = text.find(needle)
    if idx < 0:
        raise ValueError(f"needle not found: {needle!r}")
    if after:
        idx += len(needle)
    line = text.count("\n", 0, idx)
    col = idx - (text.rfind("\n", 0, idx) + 1)
    return {"line": line, "character": col}


def end_pos(text: str) -> dict:
    idx = len(text)
    line = text.count("\n")
    col = idx - (text.rfind("\n") + 1)
    return {"line": line, "character": col}


def semantic_token_type_at(src: str, data: list, offset: int) -> Optional[int]:
    """Return the semantic token type index covering `offset`, or None."""
    if offset < 0 or not data:
        return None
    line = src.count("\n", 0, offset)
    col = offset - (src.rfind("\n", 0, offset) + 1)
    pl = pc = 0
    for i in range(0, len(data) - 4, 5):
        pl += data[i]
        pc = data[i + 1] if data[i] != 0 else pc + data[i + 1]
        length = data[i + 2]
        tok_type = data[i + 3]
        if pl == line and pc <= col < pc + length:
            return tok_type
    return None


def labels(items: list[dict]) -> set[str]:
    return {it.get("label", "") for it in items}


def open_doc(c: Client, uri: str, text: str, version: int = 1) -> None:
    c.notify(
        "textDocument/didOpen",
        {
            "textDocument": {
                "uri": uri,
                "languageId": "misl",
                "version": version,
                "text": text,
            }
        },
    )
    time.sleep(0.05)  # allow recheck


def change_doc(c: Client, uri: str, text: str, version: int) -> None:
    c.notify(
        "textDocument/didChange",
        {
            "textDocument": {"uri": uri, "version": version},
            "contentChanges": [{"text": text}],
        },
    )
    time.sleep(0.03)


def complete(c: Client, uri: str, position: dict, trigger: Optional[str] = ".") -> list[dict]:
    params: dict[str, Any] = {
        "textDocument": {"uri": uri},
        "position": position,
    }
    if trigger is not None:
        params["context"] = {
            "triggerKind": 2,  # TriggerCharacter
            "triggerCharacter": trigger,
        }
    result = c.request("textDocument/completion", params)
    if result is None:
        return []
    if isinstance(result, list):
        return result
    return result.get("items") or []


def type_chars(c: Client, uri: str, base: str, insert_at: int, typed: str, start_version: int) -> tuple[str, int, dict]:
    """
    Insert `typed` into `base` at byte offset insert_at, one character at a time.
    Returns (final_text, version, position_after_last_char).
    """
    text = base
    version = start_version
    # Build prefix/suffix around insert point
    prefix = base[:insert_at]
    suffix = base[insert_at:]
    built = prefix
    for ch in typed:
        built += ch
        text = built + suffix
        version += 1
        change_doc(c, uri, text, version)
    # position after typed segment
    pos = pos_at(text, built if False else "", after=True)  # placeholder
    # compute from built length
    idx = len(built)
    line = text.count("\n", 0, idx)
    col = idx - (text.rfind("\n", 0, idx) + 1)
    return text, version, {"line": line, "character": col}


def type_until(c: Client, uri: str, prefix: str, typed_suffix: str, start_version: int = 1) -> tuple[str, int, dict]:
    """Open/replace with prefix, then type typed_suffix char-by-char. Returns text, version, caret."""
    version = start_version
    change_doc(c, uri, prefix, version)
    text = prefix
    for ch in typed_suffix:
        text += ch
        version += 1
        change_doc(c, uri, text, version)
    idx = len(text)
    # If we only typed a suffix onto a full document prefix that already ends where we type,
    # caret is at end of typed region — but prefix may be full file truncated.
    line = text.count("\n", 0, idx)
    col = idx - (text.rfind("\n", 0, idx) + 1)
    return text, version, {"line": line, "character": col}


class Suite:
    def __init__(self) -> None:
        self.fails: list[Fail] = []
        self.passes = 0

    def check(self, name: str, cond: bool, detail: str = "") -> None:
        if cond:
            self.passes += 1
            print(f"  PASS  {name}")
        else:
            self.fails.append(Fail(name, detail))
            print(f"  FAIL  {name}: {detail}")

    def expect_labels(self, name: str, items: list[dict], required: set[str], forbidden: Optional[set[str]] = None) -> None:
        got = labels(items)
        missing = required - got
        bad = (forbidden or set()) & got
        ok = not missing and not bad
        detail = f"missing={sorted(missing)} unexpected={sorted(bad)} got={sorted(got)[:40]} (n={len(got)})"
        self.check(name, ok, detail)


def make_client(
    exe: Path,
    root: Optional[Path] = None,
    init_options: Optional[dict] = None,
    process_id: Any = os.getpid(),
) -> Client:
    proc = subprocess.Popen(
        [str(exe)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=str(REPO),
    )
    c = Client(proc=proc)
    c.start_reader()

    # Drain stderr in background so pipe doesn't fill
    def _stderr() -> None:
        for _ in proc.stderr:
            pass

    threading.Thread(target=_stderr, daemon=True).start()

    root_path = root or REPO
    caps = c.request(
        "initialize",
        {
            "processId": process_id,
            "rootUri": path_uri(root_path),
            "workspaceFolders": [{"uri": path_uri(root_path), "name": root_path.name}],
            "capabilities": {
                "textDocument": {
                    "completion": {"completionItem": {"snippetSupport": False}},
                    "hover": {},
                    "definition": {},
                    "typeDefinition": {},
                    "inlayHint": {},
                    "codeAction": {},
                    "codeLens": {},
                }
            },
            "initializationOptions": init_options or {},
        },
    )
    assert caps is not None
    c.server_capabilities = (caps.get("capabilities") or {}) if isinstance(caps, dict) else {}
    c.notify("initialized", {})
    return c


# --- fixtures ---------------------------------------------------------------

MINIMAL_STRUCT = """\
S :: struct {
\tx: f32,
\ty: f32,
}
E :: enum u32 { A, B, C }
f :: proc(s: S, e: E, mp: [^]S) {
\t_ = s
\t_ = e
\t_ = mp
}
"""

MASK_SNIP = """\
Mask_Type :: enum u32 {
\tSprite,
\tCone,
}
Mask_VS_Out :: struct {
\tuv: [2]f32,
\tradius: f32,
\tmask_type: Mask_Type,
}
mask_fs :: proc(fsin: Mask_VS_Out) {
\tuv := fsin
}
"""


def run_tests(exe: Path) -> int:
    suite = Suite()
    print(f"Using server: {exe}")
    c = make_client(exe)
    uri = path_uri(REPO / "oge" / "misl" / "tools" / "misl_lsp" / "harness" / "_buf.misl")

    try:
        caps = c.server_capabilities
        suite.check("positionEncoding utf-16", caps.get("positionEncoding") == "utf-16", f"caps={caps}")
        suite.check(
            "new providers advertised",
            caps.get("inlayHintProvider") is True
            and caps.get("typeDefinitionProvider") is True
            and caps.get("codeActionProvider") is True
            and (caps.get("completionProvider") or {}).get("resolveProvider") is True,
            f"caps={caps}",
        )
        suite.check(
            "space is a completion trigger",
            " " in ((caps.get("completionProvider") or {}).get("triggerCharacters") or []),
            f"triggers={(caps.get('completionProvider') or {}).get('triggerCharacters')}",
        )
        suite.check(
            "import path completion triggers",
            {":", "/", '"'} <= set((caps.get("completionProvider") or {}).get("triggerCharacters") or []),
            f"triggers={(caps.get('completionProvider') or {}).get('triggerCharacters')}",
        )
        token_modifiers = (
            ((caps.get("semanticTokensProvider") or {}).get("legend") or {}).get("tokenModifiers")
            or []
        )
        suite.check(
            "semantic modifier legend",
            {"declaration", "defaultLibrary", "modification"} <= set(token_modifiers),
            f"modifiers={token_modifiers}",
        )

        # ========== Empty workspace (no .misl files) ==========
        print("\n== empty workspace / no misl files ==")
        empty_root = Path(tempfile.mkdtemp(prefix="misl-empty-ws-"))
        c_empty = make_client(exe, root=empty_root, process_id=None)
        try:
            suite.check("empty workspace initialize", c_empty.proc.poll() is None)
            syms = c_empty.request("workspace/symbol", {"query": ""})
            suite.check(
                "empty workspace/symbol",
                isinstance(syms, list) and len(syms) == 0,
                f"syms={syms!r}",
            )
            c_empty.notify(
                "workspace/didChangeWatchedFiles",
                {"changes": [{"uri": "untitled:untitled-1", "type": 1}]},
            )
            time.sleep(0.15)
            suite.check(
                "alive after non-file watched uri",
                c_empty.proc.poll() is None,
                f"exit={c_empty.proc.returncode}",
            )
            unknown_err = None
            try:
                c_empty.request("foo/unknownMethod", {}, timeout=2.0)
            except RuntimeError as e:
                unknown_err = str(e)
            except TimeoutError as e:
                unknown_err = f"timeout:{e}"
            suite.check(
                "unknown request returns error (not crash)",
                c_empty.proc.poll() is None and unknown_err is not None and "timeout" not in unknown_err,
                f"alive={c_empty.proc.poll() is None} err={unknown_err}",
            )
            shutdown_result = c_empty.request("shutdown", None, timeout=3.0)
            suite.check("empty workspace shutdown result is null", shutdown_result is None, f"result={shutdown_result!r}")
            c_empty.notify("exit", None)
            c_empty.proc.wait(timeout=3)
            suite.check("empty workspace exit", True)
        except Exception as e:
            suite.check("empty workspace session", False, str(e))
            try:
                c_empty.proc.kill()
            except Exception:
                pass
        finally:
            shutil.rmtree(empty_root, ignore_errors=True)

        # ========== Feature: basic open + diagnostics ==========
        print("\n== diagnostics / open ==")
        open_doc(c, uri, MINIMAL_STRUCT, 1)
        time.sleep(0.15)
        # no hard assert on diag count; just ensure server alive
        suite.check("server_alive_after_open", c.proc.poll() is None, f"exit={c.proc.returncode}")

        # ========== Completion: struct fields after s. ==========
        print("\n== completion: struct fields ==")
        text = MINIMAL_STRUCT.replace("_ = s", "_ = s.")
        change_doc(c, uri, text, 2)
        items = complete(c, uri, pos_at(text, "_ = s."), ".")
        suite.expect_labels("s. fields", items, {"x", "y"})

        # ========== Completion: 1-result call selectors ==========
        print("\n== completion: 1-result call selectors ==")
        call_src = (
            "Pair :: struct {\n"
            "\tval: f32,\n"
            "\tpad: f32,\n"
            "}\n"
            "foo :: proc() -> Pair {\n"
            "\tout: Pair\n"
            "\treturn out\n"
            "}\n"
            "foo2 :: proc() -> [3]f32 {\n"
            "\treturn [3]f32{1, 2, 3}\n"
            "}\n"
            "f :: proc() {\n"
            "\t_ = foo().\n"
            "\t_ = foo2().\n"
            "}\n"
        )
        call_uri = path_uri(REPO / "tmp_call_select_completion.misl")
        open_doc(c, call_uri, call_src, 1)
        items = complete(c, call_uri, pos_at(call_src, "_ = foo()."), ".")
        suite.expect_labels("foo(). fields", items, {"val", "pad"})
        items = complete(c, call_uri, pos_at(call_src, "_ = foo2()."), ".")
        suite.expect_labels("foo2(). swizzle", items, {"x", "y", "z"})

        # ========== Completion: using field inject ==========
        print("\n== completion: using fields ==")
        using_src = (
            "Pos :: struct {\n"
            "\tx: f32,\n"
            "\ty: f32,\n"
            "}\n"
            "E :: struct {\n"
            "\tusing pos: Pos,\n"
            "\tid: u32,\n"
            "}\n"
            "f :: proc(e: E) {\n"
            "\t_ = e.\n"
            "}\n"
        )
        using_uri = path_uri(REPO / "tmp_using_completion.misl")
        open_doc(c, using_uri, using_src, 1)
        items = complete(c, using_uri, pos_at(using_src, "_ = e."), ".")
        suite.expect_labels("e. using fields", items, {"pos", "id", "x", "y"})

        # ========== Proc group: hover/goto chosen member ==========
        print("\n== proc group hover/definition ==")
        pg_path = REPO / "oge" / "misl" / "test" / "proc_group.misl"
        pg_src = pg_path.read_text(encoding="utf-8")
        pg_uri = path_uri(pg_path)
        open_doc(c, pg_uri, pg_src, 1)
        time.sleep(0.1)
        foo_idx = pg_src.find("a := foo(1)") + len("a := ")
        foo_line = pg_src.count("\n", 0, foo_idx)
        foo_col = foo_idx - (pg_src.rfind("\n", 0, foo_idx) + 1)
        pg_hover = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": pg_uri}, "position": {"line": foo_line, "character": foo_col}},
        )
        pg_hover_val = ((pg_hover or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover proc group callsite is chosen member",
            "foo_i32" in pg_hover_val,
            f"hover={pg_hover_val!r}",
        )
        pg_locs = c.request(
            "textDocument/definition",
            {"textDocument": {"uri": pg_uri}, "position": {"line": foo_line, "character": foo_col}},
        )
        suite.check("definition proc group callsite", isinstance(pg_locs, list) and len(pg_locs) >= 1, f"locs={pg_locs}")

        legend_types = (
            ((caps.get("semanticTokensProvider") or {}).get("legend") or {}).get("tokenTypes")
            or []
        )
        function_idx = legend_types.index("function") if "function" in legend_types else -1
        class_idx = legend_types.index("class") if "class" in legend_types else -1
        print("\n== proc group semantic tokens ==")
        pg_member_off = pg_src.find("\tfoo_f32,")
        if pg_member_off >= 0:
            pg_member_off += 1  # skip tab
        try:
            pg_toks = c.request(
                "textDocument/semanticTokens/full",
                {"textDocument": {"uri": pg_uri}},
                timeout=3,
            )
            pg_data = (pg_toks or {}).get("data") or []
            hit = semantic_token_type_at(pg_src, pg_data, pg_member_off)
            suite.check(
                "multiline proc group member is function, not type",
                hit == function_idx,
                f"hit={hit} function={function_idx} class={class_idx} off={pg_member_off}",
            )
        except Exception as e:
            suite.check("multiline proc group member is function, not type", False, str(e))

        one_src = (
            "foo_f32 :: proc(x: f32) -> f32 { return x }\n"
            "one_line :: proc { foo_f32 }\n"
        )
        one_uri = path_uri(REPO / "tmp_proc_group_oneline.misl")
        open_doc(c, one_uri, one_src, 1)
        time.sleep(0.1)
        one_off = one_src.find("proc { foo_f32 }")
        if one_off >= 0:
            one_off = one_src.find("foo_f32", one_off + len("proc { "))
        try:
            one_toks = c.request(
                "textDocument/semanticTokens/full",
                {"textDocument": {"uri": one_uri}},
                timeout=3,
            )
            one_data = (one_toks or {}).get("data") or []
            hit = semantic_token_type_at(one_src, one_data, one_off)
            suite.check(
                "one-line proc group member is function, not type",
                hit == function_idx,
                f"hit={hit} function={function_idx} class={class_idx} off={one_off}",
            )
            grp_off = one_src.find("one_line ::")
            grp_hit = semantic_token_type_at(one_src, one_data, grp_off)
            suite.check(
                "one-line proc group name is function",
                grp_hit == function_idx,
                f"hit={grp_hit} function={function_idx} off={grp_off}",
            )
        except Exception as e:
            suite.check("one-line proc group member is function, not type", False, str(e))

        which_src = (
            "foo_f32 :: proc(x: f32) -> f32 { return x }\n"
            "#partial which MISL_MODE {\n"
            "case .Fmag:\n"
            "\tgrp :: proc { foo_f32 }\n"
            "}\n"
        )
        which_uri = path_uri(REPO / "tmp_proc_group_which.misl")
        open_doc(c, which_uri, which_src, 1)
        time.sleep(0.1)
        which_grp_off = which_src.find("grp ::")
        which_mem_off = which_src.find("proc { foo_f32 }")
        if which_mem_off >= 0:
            which_mem_off = which_src.find("foo_f32", which_mem_off + len("proc { "))
        try:
            which_toks = c.request(
                "textDocument/semanticTokens/full",
                {"textDocument": {"uri": which_uri}},
                timeout=3,
            )
            which_data = (which_toks or {}).get("data") or []
            suite.check(
                "fmag-which proc group name is function",
                semantic_token_type_at(which_src, which_data, which_grp_off) == function_idx,
                f"hit={semantic_token_type_at(which_src, which_data, which_grp_off)} function={function_idx} off={which_grp_off}",
            )
            suite.check(
                "fmag-which proc group member is function",
                semantic_token_type_at(which_src, which_data, which_mem_off) == function_idx,
                f"hit={semantic_token_type_at(which_src, which_data, which_mem_off)} function={function_idx} off={which_mem_off}",
            )
        except Exception as e:
            suite.check("fmag-which proc group tokens", False, str(e))

        # GPU entries are not typechecked under helper locks, so `mod.proc`
        # must still classify via the imported module — not as a variable.
        print("\n== imported proc semantic tokens ==")
        namespace_idx = legend_types.index("namespace") if "namespace" in legend_types else -1
        variable_idx = legend_types.index("variable") if "variable" in legend_types else -1
        imp_proc_src = (
            'import "core:color"\n'
            "vec3 :: [3]f32\n"
            "local_id :: proc(c: vec3) -> f32 {\n"
            "\treturn c.x\n"
            "}\n"
            'fs :: proc "fragment"() -> (out: [4]f32 | SV_Target) {\n'
            "\tseen := vec3(1, 0, 0)\n"
            "\t_ = color.luma_rec601(seen)\n"
            "\t_ = local_id(seen)\n"
            "\treturn out\n"
            "}\n"
        )
        imp_proc_uri = path_uri(REPO / "tmp_import_proc_tokens.misl")
        open_doc(c, imp_proc_uri, imp_proc_src, 1)
        time.sleep(0.1)
        call = "color.luma_rec601"
        call_off = imp_proc_src.find(call)
        color_off = call_off
        imported_proc_off = call_off + len("color.") if call_off >= 0 else -1
        local_call = "\t_ = local_id(seen)"
        local_off = imp_proc_src.find(local_call)
        if local_off >= 0:
            local_off = imp_proc_src.find("local_id", local_off)
        try:
            imp_toks = c.request(
                "textDocument/semanticTokens/full",
                {"textDocument": {"uri": imp_proc_uri}},
                timeout=3,
            )
            imp_data = (imp_toks or {}).get("data") or []
            color_hit = semantic_token_type_at(imp_proc_src, imp_data, color_off)
            imported_hit = semantic_token_type_at(imp_proc_src, imp_data, imported_proc_off)
            local_hit = semantic_token_type_at(imp_proc_src, imp_data, local_off)
            suite.check(
                "module ident at imported call is namespace",
                color_hit == namespace_idx,
                f"hit={color_hit} namespace={namespace_idx} off={color_off}",
            )
            suite.check(
                "same-file proc in gpu entry is function",
                local_hit == function_idx,
                f"hit={local_hit} function={function_idx} off={local_off}",
            )
            suite.check(
                "imported module.proc in gpu entry is function, not variable",
                imported_hit == function_idx,
                f"hit={imported_hit} function={function_idx} variable={variable_idx} off={imported_proc_off}",
            )
        except Exception as e:
            suite.check("imported module.proc in gpu entry is function, not variable", False, str(e))

        # ========== Completion: enum type name E. ==========
        print("\n== completion: Enum_Name. ==")
        text = MINIMAL_STRUCT.replace("_ = e", "_ = E.")
        change_doc(c, uri, text, 3)
        items = complete(c, uri, pos_at(text, "_ = E."), ".")
        suite.expect_labels("E. members", items, {"A", "B", "C"})

        # ========== Completion: typed implicit . ==========
        print("\n== completion: typed implicit enum ==")
        text = MINIMAL_STRUCT.replace("_ = e", "e = .")
        change_doc(c, uri, text, 4)
        items = complete(c, uri, pos_at(text, "e = ."), ".")
        suite.expect_labels("e = . members", items, {"A", "B", "C"})

        # ========== Completion: multipointer ==========
        print("\n== completion: multipointer ==")
        text = MINIMAL_STRUCT.replace("_ = mp", "_ = mp.")
        change_doc(c, uri, text, 5)
        items = complete(c, uri, pos_at(text, "_ = mp."), ".")
        # must NOT be only x,y as sole field list from peeling multipointer
        has_xy_only = labels(items) >= {"x", "y"} and len(labels(items) & {"x", "y"}) == 2 and len(items) <= 5
        suite.check("mp. does not field-complete T", not (labels(items) == {"x", "y"}), f"got={sorted(labels(items))}")

        text = MINIMAL_STRUCT.replace("_ = mp", "_ = mp[0].")
        change_doc(c, uri, text, 6)
        items = complete(c, uri, pos_at(text, "_ = mp[0]."), ".")
        suite.expect_labels("mp[0]. fields", items, {"x", "y"})

        # ========== Completion: core:debug members after debug. ==========
        print("\n== completion: core:debug members ==")
        debug_src = (
            'import "core:debug"\n'
            "f :: proc() {\n"
            "\tdebug.\n"
            "}\n"
        )
        debug_uri = path_uri(REPO / "tmp_debug_completion.misl")
        open_doc(c, debug_uri, debug_src, 1)
        items = complete(c, debug_uri, pos_at(debug_src, "debug."), ".")
        suite.expect_labels(
            "debug. procs",
            items,
            {"printf", "printfln", "assert", "panic"},
            {"sin", "cos"},
        )

        print("\n== completion: core:wave members ==")
        wave_src = (
            'import "core:wave"\n'
            "f :: proc() {\n"
            "\twave.\n"
            "}\n"
        )
        wave_uri = path_uri(REPO / "tmp_wave_completion.misl")
        open_doc(c, wave_uri, wave_src, 1)
        items = complete(c, wave_uri, pos_at(wave_src, "wave."), ".")
        suite.expect_labels(
            "wave. procs",
            items,
            {"sum", "prefix_sum", "shuffle_xor", "clustered_sum", "rotate", "quad_x"},
            {"sin", "cos"},
        )

        # ========== Completion: import paths ==========
        print("\n== completion: import paths ==")
        imp_uri = path_uri(REPO / "oge" / "misl" / "test" / "_lsp_import_complete.misl")
        quote_src = 'import "'
        open_doc(c, imp_uri, quote_src, 1)
        items = complete(c, imp_uri, pos_at(quote_src, 'import "'), '"')
        suite.expect_labels(
            'import " collections',
            items,
            {"core:", "lib:"},
            {"core:builtin", "sin"},
        )
        suite.check(
            'import " offers relative folder',
            "import_deps/" in labels(items),
            f"got={sorted(labels(items))[:40]}",
        )

        core_src = 'import "core:'
        change_doc(c, imp_uri, core_src, 2)
        items = complete(c, imp_uri, pos_at(core_src, 'import "core:'), ":")
        suite.expect_labels(
            "core: synthetics and baked files",
            items,
            {"core:builtin", "core:debug", "core:wave", "core:s2h.misl", "core:fmag.misl"},
            {"core:", "sin"},
        )

        lib_src = 'import "lib:'
        change_doc(c, imp_uri, lib_src, 3)
        items = complete(c, imp_uri, pos_at(lib_src, 'import "lib:'), ":")
        suite.expect_labels("lib: files", items, {"lib:math.misl"})

        rel_src = 'import "import_deps/'
        change_doc(c, imp_uri, rel_src, 4)
        items = complete(c, imp_uri, pos_at(rel_src, 'import "import_deps/'), "/")
        suite.expect_labels(
            "relative import_deps/",
            items,
            {"import_deps/common.misl"},
            {"core:builtin", "core:"},
        )

        typed_src = "x: \n"
        typed_uri = path_uri(REPO / "tmp_colon_not_import.misl")
        open_doc(c, typed_uri, typed_src, 1)
        items = complete(c, typed_uri, pos_at(typed_src, "x:"), ":")
        suite.check(
            ": outside import is not ident dump",
            "sin" not in labels(items) and "core:" not in labels(items),
            f"got={sorted(labels(items))[:20]}",
        )

        # ========== Completion: #+ file tags ==========
        print("\n== completion: #+ file tags ==")
        tag_uri = path_uri(REPO / "tmp_file_tag.misl")
        tag_src = "#+\n"
        open_doc(c, tag_uri, tag_src, 1)
        items = complete(c, tag_uri, pos_at(tag_src, "#+"), "+")
        suite.expect_labels(
            "#+ directives",
            items,
            {"feature"},
            {"align", "config", "no_bounds_check", "disable-asserts"},
        )
        feat_src = "#+feature \n"
        change_doc(c, tag_uri, feat_src, 2)
        items = complete(c, tag_uri, pos_at(feat_src, "#+feature "), " ")
        suite.expect_labels(
            "#+feature names on space",
            items,
            {"no_bounds_check", "disable-asserts"},
            {"feature", "align", "config"},
        )
        items = complete(c, tag_uri, pos_at(feat_src, "#+feature "), None)
        suite.expect_labels(
            "#+feature names",
            items,
            {"no_bounds_check", "disable-asserts"},
            {"feature", "align", "config"},
        )
        partial_src = "#+fe\n"
        change_doc(c, tag_uri, partial_src, 3)
        items = complete(c, tag_uri, pos_at(partial_src, "#+fe"), None)
        suite.expect_labels(
            "#+fe still offers feature",
            items,
            {"feature"},
            {"align", "no_bounds_check"},
        )
        feat_item = next((i for i in items if i.get("label") == "feature"), None)
        suite.check(
            "feature insertText ends with space",
            isinstance(feat_item, dict) and str(feat_item.get("insertText", "")).endswith(" "),
            f"item={feat_item}",
        )
        cmd = (feat_item or {}).get("command") or {}
        suite.check(
            "feature retriggers suggest",
            cmd.get("command") == "editor.action.triggerSuggest",
            f"command={cmd}",
        )
        space_src = 'entry :: proc "vertex"() { x := 1 }\n'
        change_doc(c, tag_uri, space_src, 4)
        items = complete(c, tag_uri, pos_at(space_src, "x := "), " ")
        suite.check(
            "space elsewhere does not complete",
            items == [],
            f"labs={[i.get('label') for i in items[:8]]}",
        )

        # ========== Completion: shader stage strings ==========
        print("\n== completion: proc stage ==")
        stage_src = 'entry :: proc "vertex"() {}\n'
        change_doc(c, uri, stage_src, 7)
        items = complete(c, uri, pos_at(stage_src, 'proc "ver'), '"')
        suite.expect_labels("proc stage completion", items, {"vertex", "fragment", "compute", "fmag"})
        stage_pos = pos_at(stage_src, "proc", after=False)
        stage_actions = c.request(
            "textDocument/codeAction",
            {
                "textDocument": {"uri": uri},
                "range": {"start": stage_pos, "end": stage_pos},
                "context": {"diagnostics": []},
            },
        )
        suite.check(
            "empty stage proc stub action",
            any((a.get("title") or "").startswith("Expand vertex shader") for a in (stage_actions or [])),
            f"actions={stage_actions}",
        )

        # ========== FMAG: completion / hover / stub / GLSL ==========
        print("\n== fmag ==")
        fmag_src = (
            'import "core:fmag"\n'
            "shade :: proc \"fmag\"(x: f32) -> f32 {\n"
            "\t_ = x\n"
            "\treturn x\n"
            "}\n"
            "use :: proc() {\n"
            "\t_ = shade(1)\n"
            "\t_ = f32_from_u32_bits(0)\n"
            "\tfmag.\n"
            "}\n"
        )
        fmag_uri = path_uri(REPO / "tmp_fmag_lsp.misl")
        open_doc(c, fmag_uri, fmag_src, 1)
        time.sleep(0.1)
        items = complete(c, fmag_uri, pos_at(fmag_src, "_ = x"), None)
        suite.expect_labels(
            "fmag body allows math + bitcasts",
            items,
            {"fma", "sin", "f32_from_u32_bits", "u32_from_f32_bits", "x"},
            {"sample", "load", "store", "dim", "dFdx", "dFdy", "fwidth", "barrier", "sin_f32"},
        )
        items = complete(c, fmag_uri, pos_at(fmag_src, "_ = shade"), None)
        suite.expect_labels("non-fmag body still has sample", items, {"sample"})
        items = complete(c, fmag_uri, pos_at(fmag_src, "fmag."), ".")
        suite.expect_labels("fmag. interpreter members", items, {"run", "step_packet", "load_op", "REGS"})
        fh = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": fmag_uri}, "position": pos_at(fmag_src, "shade ::", after=False)},
        )
        fh_val = ((fh or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover proc fmag signature",
            'proc "fmag"' in fh_val and "compile_fmag_entry" in fh_val,
            f"hover={fh_val!r}",
        )
        fh_call = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": fmag_uri}, "position": pos_at(fmag_src, "shade(1)", after=False)},
        )
        fh_call_val = ((fh_call or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover proc fmag callsite",
            'proc "fmag"' in fh_call_val,
            f"hover={fh_call_val!r}",
        )
        bit_h = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": fmag_uri}, "position": pos_at(fmag_src, "f32_from_u32_bits", after=False)},
        )
        bit_val = ((bit_h or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover bitcast builtin",
            "f32_from_u32_bits" in bit_val and "uintBitsToFloat" in bit_val,
            f"hover={bit_val!r}",
        )
        run_src = (
            'import "core:fmag"\n'
            "use :: proc(code: [][4]u32, #ref r: [16]f32) {\n"
            "\tfmag.run(code, &r)\n"
            "}\n"
        )
        change_doc(c, fmag_uri, run_src, 2)
        time.sleep(0.08)
        run_h = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": fmag_uri}, "position": pos_at(run_src, "run(code", after=False)},
        )
        run_val = ((run_h or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover fmag.run docs",
            "run" in run_val and ("REGS" in run_val or "compile_fmag_entry" in run_val or "packet" in run_val.lower()),
            f"hover={run_val!r}",
        )
        shade_only = (
            "shade :: proc \"fmag\"(x: f32) -> f32 {\n"
            "\treturn x + x\n"
            "}\n"
        )
        change_doc(c, fmag_uri, shade_only, 3)
        time.sleep(0.08)
        fmag_syms = c.request("textDocument/documentSymbol", {"textDocument": {"uri": fmag_uri}})
        shade_sym = next((s for s in (fmag_syms or []) if s.get("name") == "shade"), {})
        suite.check(
            "document symbol fmag detail",
            (shade_sym.get("detail") or "") == 'proc "fmag"',
            f"sym={shade_sym}",
        )
        try:
            prev = c.request("misl/fmagPreview", {"uri": fmag_uri, "entity": "shade"})
            ftext = (prev or {}).get("fmag") or ""
            suite.check(
                "fmagPreview shade has packets",
                isinstance(prev, dict) and ".def shade" in ftext and "fmag" in ftext,
                f"fmag={ftext[:400]!r}",
            )
        except Exception as e:
            suite.check("fmagPreview shade has packets", False, str(e))
        fmag_lenses = c.request("textDocument/codeLens", {"textDocument": {"uri": fmag_uri}})
        shade_cmd = {}
        for lens in fmag_lenses or []:
            cmd = lens.get("command") or {}
            if cmd.get("command") == "misl.showFmag":
                shade_cmd = cmd
                break
        suite.check(
            "codeLens command misl.showFmag",
            shade_cmd.get("command") == "misl.showFmag",
            f"lenses={fmag_lenses}",
        )
        try:
            fprev = c.request("misl/fmagPreview", {"uri": fmag_uri, "entity": "shade"})
            ftext = (fprev or {}).get("fmag") or ""
            suite.check(
                "fmagPreview returns asm",
                isinstance(fprev, dict) and ".def shade" in ftext and "fmag" in ftext,
                f"fmag={ftext[:400]!r}",
            )
        except Exception as e:
            suite.check("fmagPreview returns asm", False, str(e))

        stub_src = 'entry :: proc "fmag"() {}\n'
        change_doc(c, fmag_uri, stub_src, 4)
        stub_pos = pos_at(stub_src, "proc", after=False)
        stub_actions = c.request(
            "textDocument/codeAction",
            {
                "textDocument": {"uri": fmag_uri},
                "range": {"start": stub_pos, "end": stub_pos},
                "context": {"diagnostics": []},
            },
        )
        stub = next(
            (a for a in (stub_actions or []) if (a.get("title") or "") == "Expand fmag kernel stub"),
            None,
        )
        stub_text = ""
        if stub:
            changes = ((stub.get("edit") or {}).get("documentChanges") or [])
            stub_text = "".join(
                edit.get("newText") or ""
                for change in changes
                for edit in (change.get("edits") or [])
            )
        suite.check(
            "empty fmag proc stub action",
            stub is not None and 'proc "fmag"' in stub_text and "return albedo * light" in stub_text,
            f"actions={stub_actions} text={stub_text!r}",
        )

        print("\n== MISL_MODE completion visibility ==")
        kb_src = (
            "vs :: proc \"vertex\"() {\n"
            "\t_ = 0\n"
            "}\n"
            "fs :: proc \"fragment\"() {\n"
            "\t_ = 0\n"
            "}\n"
            "help :: proc() {\n"
            "\t_ = 0\n"
            "}\n"
            "shade :: proc \"fmag\"(x: f32) -> f32 {\n"
            "\t_ = x\n"
            "\treturn x\n"
            "}\n"
        )
        kb_uri = path_uri(REPO / "tmp_kernel_lsp.misl")
        open_doc(c, kb_uri, kb_src, 1)
        time.sleep(0.1)
        items = complete(c, kb_uri, pos_at(kb_src, "vs :: proc \"vertex\"() {\n\t"), None)
        suite.expect_labels("vertex body has sample and fwidth", items, {"sample", "fwidth"})
        items = complete(c, kb_uri, pos_at(kb_src, "fs :: proc \"fragment\"() {\n\t"), None)
        suite.expect_labels("fragment body has fwidth", items, {"fwidth", "sample"})
        items = complete(c, kb_uri, pos_at(kb_src, "help :: proc() {\n\t"), None)
        suite.expect_labels("helper body has sample and fwidth", items, {"sample", "fwidth"})
        items = complete(c, kb_uri, pos_at(kb_src, "shade :: proc \"fmag\"(x: f32) -> f32 {\n\t"), None)
        suite.expect_labels("fmag body has no sample", items, {"x", "sin"}, {"sample", "fwidth", "sin_f32"})

        print("\n== Show SPIRV vs Show FMAG sin ==")
        split_src = (
            "Data :: struct #align(16) { color: [4]f32 }\n"
            "VS_Out :: struct { pos: [4]f32 | SV_Position }\n"
            "vs :: proc \"vertex\"(data: ^Data | SV_Data, vertex_id: u32 | SV_Vertex) -> (out: VS_Out) {\n"
            "\t_ = data\n"
            "\t_ = vertex_id\n"
            "\tout.pos = [4]f32{sin(0.5), 0, 0, 1}\n"
            "\treturn out\n"
            "}\n"
            "shade :: proc \"fmag\"(x: f32) -> f32 {\n"
            "\treturn sin(x)\n"
            "}\n"
        )
        split_uri = path_uri(REPO / "tmp_fmag_sin_split.misl")
        open_doc(c, split_uri, split_src, 1)
        time.sleep(0.1)
        split_lenses = c.request("textDocument/codeLens", {"textDocument": {"uri": split_uri}})
        vs_cmds = set()
        for lens in split_lenses or []:
            cmd = lens.get("command") or {}
            args = cmd.get("arguments") or []
            if len(args) >= 2 and args[1] == "vs":
                vs_cmds.add(cmd.get("command"))
        suite.check(
            "codeLens Show SPIRV on vs",
            {"misl.showSpirv"} <= vs_cmds,
            f"cmds={sorted(vs_cmds)} lenses={split_lenses}",
        )
        suite.check(
            "codeLens has no Show GLSL",
            "misl.showGlsl" not in vs_cmds,
            f"cmds={sorted(vs_cmds)}",
        )
        try:
            sprev = c.request("misl/spirvPreview", {"uri": split_uri, "entity": "vs"})
            stext = (sprev or {}).get("spirv") or ""
            suite.check(
                "spirvPreview vs contains OpEntryPoint",
                isinstance(sprev, dict) and "OpEntryPoint" in stext and "vs" in stext,
                f"spirv={stext[:500]!r}",
            )
            suite.check(
                "spirvPreview does not embed MISL source",
                "vs :: proc" not in stext and "proc \"vertex\"" not in stext,
                f"spirv={stext[:500]!r}",
            )
        except Exception as e:
            suite.check("spirvPreview vs contains OpEntryPoint", False, str(e))
        try:
            fprev = c.request("misl/fmagPreview", {"uri": split_uri, "entity": "shade"})
            ftext = (fprev or {}).get("fmag") or ""
            suite.check(
                "fmagPreview shade has packets, not GLSL sin(",
                isinstance(fprev, dict)
                and ".def shade" in ftext
                and "fmag" in ftext
                and not fmag_instr_contains(ftext, "sin("),
                f"fmag={ftext[:500]!r}",
            )
        except Exception as e:
            suite.check("fmagPreview shade has packets, not GLSL sin(", False, str(e))

        # ========== Completion: compound literals ==========
        print("\n== completion: compound literals ==")
        comp_src = (
            "E :: enum u32 { A, B, C }\n"
            "Flags :: bit_set[E; u32]\n"
            "S :: struct { x: i32, y: i32, e: E }\n"
            "take :: proc(v: S) {}\n"
            "f :: proc() {\n"
            "\ts := S{x = 1, }\n"
            "\tb: Flags = {.}\n"
            "\ttake({})\n"
            "}\n"
        )
        change_doc(c, uri, comp_src, 8)
        items = complete(c, uri, pos_at(comp_src, "S{x = 1, "), None)
        suite.expect_labels("struct comp-lit remaining fields", items, {"y", "e"}, {"x"})
        y_item = next((i for i in items if i.get("label") == "y"), {})
        suite.check(
            "struct comp-lit field snippet",
            y_item.get("insertText") == "y = $0" and y_item.get("insertTextFormat") == 2,
            f"item={y_item}",
        )
        items = complete(c, uri, pos_at(comp_src, "b: Flags = {."), ".")
        suite.expect_labels("inferred bit-set comp-lit members", items, {"A", "B", "C"})
        items = complete(c, uri, pos_at(comp_src, "take({"), None)
        suite.expect_labels("call-param inferred comp-lit fields", items, {"x", "y", "e"})

        # ========== Character-by-character: fsin. ==========
        print("\n== typing char-by-char: fsin. ==")
        base = (
            "Mask_Type :: enum u32 {\n"
            "\tSprite,\n"
            "\tCone,\n"
            "}\n"
            "Mask_VS_Out :: struct {\n"
            "\tuv: [2]f32,\n"
            "\tradius: f32,\n"
            "\tmask_type: Mask_Type,\n"
            "}\n"
            "mask_fs :: proc(fsin: Mask_VS_Out) {\n"
            "\tuv := fsin"
        )
        change_doc(c, uri, base, 10)
        ver = 10
        # type '.' then close the proc with a following line (simulates Enter after dot)
        text = base
        for ch in ".":
            text += ch
            ver += 1
            change_doc(c, uri, text, ver)
        text2 = text + "\n}\n"
        ver += 1
        change_doc(c, uri, text2, ver)
        caret = pos_at(text2, "uv := fsin.")
        items = complete(c, uri, caret, ".")
        suite.expect_labels("typed fsin. fields", items, {"uv", "radius", "mask_type"})

        print("\n== typing fsin. with next-line ident (newline recovery) ==")
        before_dot = (
            "Mask_Type :: enum u32 { Sprite, Cone }\n"
            "Mask_VS_Out :: struct { uv: [2]f32, radius: f32, mask_type: Mask_Type }\n"
            "mask_fs :: proc(fsin: Mask_VS_Out) {\n"
            "\tuv := fsin\n"
            "\tcenter := vec2(0.5, 0.5)\n"
            "}\n"
        )
        change_doc(c, uri, before_dot, ver + 1)
        ver += 1
        anchor = before_dot.find("uv := fsin")
        suite.check("anchor uv := fsin", anchor >= 0, "missing uv := fsin")
        idx = anchor + len("uv := fsin")
        text = before_dot[:idx] + "." + before_dot[idx:]
        ver += 1
        change_doc(c, uri, text, ver)
        suite.check("alive after fsin.\\ncenter", c.proc.poll() is None, f"exit={c.proc.returncode}")
        caret = pos_at(text, "uv := fsin.")
        items = complete(c, uri, caret, ".")
        suite.expect_labels("fsin. before center:= fields", items, {"uv", "radius", "mask_type"})

        print("\n== typing char-by-char: == . ==")
        eq_base = (
            "Mask_Type :: enum u32 { Sprite, Cone }\n"
            "Mask_VS_Out :: struct { uv: [2]f32, mask_type: Mask_Type }\n"
            "mask_fs :: proc(fsin: Mask_VS_Out) {\n"
            "\tif fsin.mask_type == \n"
            "}\n"
        )
        change_doc(c, uri, eq_base, ver + 1)
        ver += 1
        idx = eq_base.find("if fsin.mask_type == ") + len("if fsin.mask_type == ")
        prefix, suffix = eq_base[:idx], eq_base[idx:]
        cur = prefix
        for ch in ".":
            cur += ch
            text = cur + suffix
            ver += 1
            change_doc(c, uri, text, ver)
        suite.check("server_alive_after_eq_dot", c.proc.poll() is None, f"exit={c.proc.returncode}")
        caret = pos_at(text, "if fsin.mask_type == .")
        try:
            items = complete(c, uri, caret, ".")
            suite.expect_labels("== . enum members", items, {"Sprite", "Cone"})
        except Exception as e:
            suite.check("== . completion no crash", False, str(e))

        print("\n== typing full ' == .' after mask_type ==")
        stem = (
            "Mask_Type :: enum u32 { Sprite, Cone }\n"
            "Mask_VS_Out :: struct { mask_type: Mask_Type }\n"
            "mask_fs :: proc(fsin: Mask_VS_Out) {\n"
            "\tif fsin.mask_type\n"
            "}\n"
        )
        change_doc(c, uri, stem, ver + 1)
        ver += 1
        idx = stem.find("if fsin.mask_type") + len("if fsin.mask_type")
        prefix, suffix = stem[:idx], stem[idx:]
        cur = prefix
        died = False
        for ch in " == .":
            cur += ch
            text = cur + suffix
            ver += 1
            change_doc(c, uri, text, ver)
            if c.proc.poll() is not None:
                suite.check("alive while typing == .", False, f"died after {ch!r} code={c.proc.returncode}")
                died = True
                break
        if not died:
            suite.check("alive while typing == .", True)
            caret = pos_at(text, "if fsin.mask_type == .")
            items = complete(c, uri, caret, ".")
            suite.expect_labels("typed == . members", items, {"Sprite", "Cone"})

        # ========== Hover ==========
        print("\n== hover ==")
        change_doc(c, uri, MINIMAL_STRUCT, ver + 1)
        ver += 1
        h = c.request("textDocument/hover", {"textDocument": {"uri": uri}, "position": pos_at(MINIMAL_STRUCT, "S ::", after=False)})
        h_val = ((h or {}).get("contents") or {}).get("value") or ""
        suite.check("hover on S", h is not None and bool(h), f"hover={h}")
        suite.check(
            "hover S shows struct definition",
            "S :: struct" in h_val and "x:" in h_val and "y:" in h_val and "f32" in h_val,
            f"hover={h_val!r}",
        )
        he_type = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": uri}, "position": pos_at(MINIMAL_STRUCT, "E ::", after=False)},
        )
        he_type_val = ((he_type or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover E shows enum definition",
            "E :: enum" in he_type_val and "A" in he_type_val and "B" in he_type_val and "u32" in he_type_val,
            f"hover={he_type_val!r}",
        )
        # Variable of named struct/enum must include the type name (OLS-style `name: Type`)
        hs = c.request("textDocument/hover", {"textDocument": {"uri": uri}, "position": pos_at(MINIMAL_STRUCT, "_ = ", after=True)})
        hs_val = ((hs or {}).get("contents") or {}).get("value") or ""
        suite.check("hover var s shows type S", "s: S" in hs_val, f"hover={hs_val!r}")
        e_idx = MINIMAL_STRUCT.find("_ = e") + 4
        e_line = MINIMAL_STRUCT.count("\n", 0, e_idx)
        e_col = e_idx - (MINIMAL_STRUCT.rfind("\n", 0, e_idx) + 1)
        he = c.request("textDocument/hover", {"textDocument": {"uri": uri}, "position": {"line": e_line, "character": e_col}})
        he_val = ((he or {}).get("contents") or {}).get("value") or ""
        suite.check("hover var e shows type E", "e: E" in he_val, f"hover={he_val!r}")

        # SV_* semantic hover docs
        sem_src = (
            "package main\n"
            "Out :: struct {\n"
            "\tpos: [4]f32 | SV_Position,\n"
            "}\n"
        )
        sem_uri = path_uri(REPO / "tmp_sem_hover.misl")
        open_doc(c, sem_uri, sem_src, 1)
        time.sleep(0.08)
        idx = sem_src.find("SV_Position")
        line = sem_src.count("\n", 0, idx)
        col = idx - (sem_src.rfind("\n", 0, idx) + 1)
        sh = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": sem_uri}, "position": {"line": line, "character": col}},
        )
        sh_val = ((sh or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover SV_Position docs",
            "```misl\nSV_Position\n```" in sh_val and "gl_Position" in sh_val and "---" in sh_val,
            f"hover={sh_val!r}",
        )

        docs_src = (
            "// Doubles a value for shader math.\n"
            "documented :: proc(value: i32) -> i32 {\n"
            "\treturn value + value\n"
            "}\n"
            "caller :: proc() {\n"
            "\t_ = documented(2)\n"
            "}\n"
        )
        docs_uri = path_uri(REPO / "tmp_docs_hover.misl")
        open_doc(c, docs_uri, docs_src, 1)
        docs_hover = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": docs_uri}, "position": pos_at(docs_src, "documented(2)", after=False)},
        )
        docs_hover_val = ((docs_hover or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover includes leading docs",
            "Doubles a value for shader math." in docs_hover_val and "---" in docs_hover_val,
            f"hover={docs_hover_val!r}",
        )

        def hover_sig(val: str) -> str:
            return (val or "").replace("\u200b", "").replace("\\$", "$")

        poly_path = REPO / "oge" / "misl" / "test" / "parapoly_scalar.misl"
        poly_src = poly_path.read_text(encoding="utf-8")
        poly_uri = path_uri(poly_path)
        open_doc(c, poly_uri, poly_src, 1)
        time.sleep(0.1)
        poly_def = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": poly_uri}, "position": pos_at(poly_src, "add_n ::", after=False)},
        )
        poly_def_val = hover_sig(((poly_def or {}).get("contents") or {}).get("value") or "")
        suite.check(
            "hover parapoly proc shows $n",
            "add_n :: proc($n: i32) -> i32" in poly_def_val,
            f"hover={poly_def_val!r}",
        )
        poly_call = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": poly_uri}, "position": pos_at(poly_src, "add_n(3)", after=False)},
        )
        poly_call_val = hover_sig(((poly_call or {}).get("contents") or {}).get("value") or "")
        suite.check(
            "hover parapoly callsite shows $n",
            "add_n :: proc($n: i32) -> i32" in poly_call_val,
            f"hover={poly_call_val!r}",
        )
        n_idx = poly_src.find("$n")
        suite.check("parapoly source has $n", n_idx >= 0)
        n_line = poly_src.count("\n", 0, n_idx + 1)
        n_col = (n_idx + 1) - (poly_src.rfind("\n", 0, n_idx + 1) + 1)
        poly_param = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": poly_uri}, "position": {"line": n_line, "character": n_col}},
        )
        poly_param_val = hover_sig(((poly_param or {}).get("contents") or {}).get("value") or "")
        suite.check(
            "hover parapoly param shows $n: i32",
            "$n: i32" in poly_param_val,
            f"hover={poly_param_val!r}",
        )
        poly_sh = c.request(
            "textDocument/signatureHelp",
            {"textDocument": {"uri": poly_uri}, "position": pos_at(poly_src, "add_n(", after=True)},
        )
        poly_sh_label = ""
        sigs = (poly_sh or {}).get("signatures") or []
        if sigs:
            poly_sh_label = sigs[0].get("label") or ""
        suite.check(
            "signature help parapoly shows $n",
            "$n: i32" in poly_sh_label,
            f"label={poly_sh_label!r}",
        )

        inout_src = (
            "Obj :: struct { x: i32 }\n"
            "set_obj :: proc(#ref obj: Obj, n: i32) {\n"
            "\tobj.x = n\n"
            "}\n"
            "use_obj :: proc() {\n"
            "\to := Obj{}\n"
            "\tset_obj(&o, 1)\n"
            "}\n"
            "Varying :: struct {\n"
            "\t#flat id: u32,\n"
            "}\n"
        )
        inout_uri = path_uri(REPO / "tmp_inout_hover.misl")
        open_doc(c, inout_uri, inout_src, 1)
        time.sleep(0.1)
        inout_def = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": inout_uri}, "position": pos_at(inout_src, "set_obj ::", after=False)},
        )
        inout_def_val = hover_sig(((inout_def or {}).get("contents") or {}).get("value") or "")
        suite.check(
            "hover #ref proc shows #ref",
            "set_obj :: proc(#ref obj: Obj, n: i32)" in inout_def_val,
            f"hover={inout_def_val!r}",
        )
        inout_call = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": inout_uri}, "position": pos_at(inout_src, "set_obj(&o", after=False)},
        )
        inout_call_val = hover_sig(((inout_call or {}).get("contents") or {}).get("value") or "")
        suite.check(
            "hover #ref callsite shows #ref",
            "set_obj :: proc(#ref obj: Obj, n: i32)" in inout_call_val,
            f"hover={inout_call_val!r}",
        )
        inout_param = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": inout_uri}, "position": pos_at(inout_src, "obj: Obj", after=False)},
        )
        inout_param_val = hover_sig(((inout_param or {}).get("contents") or {}).get("value") or "")
        suite.check(
            "hover #ref param shows #ref obj: Obj",
            "#ref obj: Obj" in inout_param_val,
            f"hover={inout_param_val!r}",
        )
        inout_sh = c.request(
            "textDocument/signatureHelp",
            {"textDocument": {"uri": inout_uri}, "position": pos_at(inout_src, "set_obj(", after=True)},
        )
        inout_sh_label = ""
        inout_sigs = (inout_sh or {}).get("signatures") or []
        if inout_sigs:
            inout_sh_label = inout_sigs[0].get("label") or ""
        suite.check(
            "signature help #ref shows #ref",
            "#ref obj: Obj" in inout_sh_label,
            f"label={inout_sh_label!r}",
        )
        flat_hover = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": inout_uri}, "position": pos_at(inout_src, "Varying ::", after=False)},
        )
        flat_val = hover_sig(((flat_hover or {}).get("contents") or {}).get("value") or "")
        suite.check(
            "hover struct shows #flat field",
            "#flat id:" in flat_val,
            f"hover={flat_val!r}",
        )
        resolved = c.request(
            "completionItem/resolve",
            {"label": "documented", "kind": 3},
        )
        resolved_docs = ((resolved or {}).get("documentation") or {}).get("value") or ""
        suite.check(
            "completion resolve documentation",
            "Doubles a value for shader math." in resolved_docs,
            f"resolved={resolved}",
        )

        # ========== Definition ==========
        print("\n== definition ==")
        # jump from use of S in param
        dpos = pos_at(MINIMAL_STRUCT, "s: S", after=True)
        # position on S in `s: S`
        idx = MINIMAL_STRUCT.find("s: S") + 3
        line = MINIMAL_STRUCT.count("\n", 0, idx)
        col = idx - (MINIMAL_STRUCT.rfind("\n", 0, idx) + 1)
        locs = c.request("textDocument/definition", {"textDocument": {"uri": uri}, "position": {"line": line, "character": col}})
        suite.check("definition S", isinstance(locs, list) and len(locs) >= 1, f"locs={locs}")

        # Implicit enum member definition
        text = MINIMAL_STRUCT.replace("_ = e", "e = .A")
        change_doc(c, uri, text, ver + 1)
        ver += 1
        idx = text.find("e = .A") + len("e = .")
        line = text.count("\n", 0, idx)
        col = idx - (text.rfind("\n", 0, idx) + 1)
        locs = c.request("textDocument/definition", {"textDocument": {"uri": uri}, "position": {"line": line, "character": col}})
        suite.check("definition .A", isinstance(locs, list) and len(locs) >= 1, f"locs={locs}")

        type_locs = c.request(
            "textDocument/typeDefinition",
            {
                "textDocument": {"uri": uri},
                "position": pos_at(MINIMAL_STRUCT, "_ = ", after=True),
            },
        )
        suite.check(
            "typeDefinition variable to S",
            isinstance(type_locs, list)
            and len(type_locs) == 1
            and type_locs[0].get("uri") == uri
            and ((type_locs[0].get("range") or {}).get("start") or {}).get("line") == 0,
            f"locs={type_locs}",
        )

        # ========== Signature help ==========
        print("\n== signature help ==")
        sig_src = MINIMAL_STRUCT.replace("_ = s", "_ = f(")
        change_doc(c, uri, sig_src, ver + 1)
        ver += 1
        try:
            sh = c.request(
                "textDocument/signatureHelp",
                {
                    "textDocument": {"uri": uri},
                    "position": pos_at(sig_src, "_ = f("),
                    "context": {"triggerKind": 2, "triggerCharacter": "("},
                },
            )
            suite.check("signatureHelp", sh is not None, f"sh={sh}")
        except Exception as e:
            suite.check("signatureHelp", False, str(e))

        printf_src = (
            'import "core:debug"\n'
            "f :: proc() {\n"
            '\tdebug.printf("two %v %#v", 1, 2)\n'
            "}\n"
        )
        printf_uri = path_uri(REPO / "tmp_printf_signature.misl")
        open_doc(c, printf_uri, printf_src, 1)
        printf_sig = c.request(
            "textDocument/signatureHelp",
            {
                "textDocument": {"uri": printf_uri},
                "position": pos_at(printf_src, 'debug.printf("two %v %#v", 1,'),
                "context": {"triggerKind": 2, "triggerCharacter": ","},
            },
        )
        printf_label = ((((printf_sig or {}).get("signatures") or [{}])[0]).get("label") or "")
        suite.check(
            "printf signature dynamic slots",
            "%v: any" in printf_label and "%#v: any" in printf_label,
            f"label={printf_label!r}",
        )

        links = c.request("textDocument/documentLink", {"textDocument": {"uri": printf_uri}})
        suite.check(
            "builtins are not document-linked (no underline)",
            links is None or links == [],
            f"links={links}",
        )
        printf_hover = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": printf_uri}, "position": pos_at(printf_src, "printf", after=False)},
        )
        printf_hover_val = ((printf_hover or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "builtin hover still has docs + optional language reference",
            "printf" in printf_hover_val.lower() or "print" in printf_hover_val.lower(),
            f"hover={printf_hover_val!r}",
        )
        printf_inlays = c.request(
            "textDocument/inlayHint",
            {
                "textDocument": {"uri": printf_uri},
                "range": {"start": {"line": 0, "character": 0}, "end": end_pos(printf_src)},
            },
        )
        printf_inlay_labels = {hint.get("label") for hint in (printf_inlays or [])}
        suite.check(
            "builtin printf inlay labels",
            {"format:", "%v:", "%#v:"} <= printf_inlay_labels,
            f"labels={sorted(printf_inlay_labels)}",
        )

        # ========== #intrinsic builtins: hover / complete / signature / definition ==========
        print("\n== intrinsic abs + t32_2d hover/def ==")
        abs_src = (
            "vs :: proc \"vertex\"(\n"
            "\tvid: u32 | SV_Vertex,\n"
            ") -> (out: [4]f32 | SV_Position) {\n"
            "\tx: f32 = abs(-1.5)\n"
            "\ttex: t32_2d = 0\n"
            "\t_ = vid\n"
            "\tout = [4]f32{x, 0, 0, 1}\n"
            "\treturn out\n"
            "}\n"
        )
        abs_uri = path_uri(REPO / "tmp_intrinsic_abs.misl")
        open_doc(c, abs_uri, abs_src, 1)
        abs_hover = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": abs_uri}, "position": pos_at(abs_src, "abs(", after=False)},
        )
        abs_hover_val = ((abs_hover or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover abs has genType and name",
            "abs" in abs_hover_val and "genType" in abs_hover_val,
            f"hover={abs_hover_val!r}",
        )
        t32_hover = c.request(
            "textDocument/hover",
            {"textDocument": {"uri": abs_uri}, "position": pos_at(abs_src, "t32_2d =", after=False)},
        )
        t32_hover_val = ((t32_hover or {}).get("contents") or {}).get("value") or ""
        suite.check(
            "hover t32_2d is a type",
            "t32_2d" in t32_hover_val and "#intrinsic" not in t32_hover_val,
            f"hover={t32_hover_val!r}",
        )
        abs_items = complete(c, abs_uri, pos_at(abs_src, "x: f32 = "), None)
        abs_item = next((it for it in abs_items if it.get("label") == "abs"), None)
        suite.check(
            "completion abs snippet + genType",
            abs_item is not None
            and "abs($0)" in (abs_item.get("insertText") or "")
            and "genType" in ((abs_item.get("detail") or "") + str(abs_item.get("labelDetails") or "")),
            f"item={abs_item}",
        )
        t32_item = next((it for it in abs_items if it.get("label") == "t32_2d"), None)
        suite.check(
            "completion t32_2d is a type not a function snippet",
            t32_item is not None and "($0)" not in (t32_item.get("insertText") or "t32_2d"),
            f"item={t32_item}",
        )
        t32_old = next((it for it in abs_items if it.get("label") == "t32"), None)
        suite.check(
            "no unsuffixed t32 completion",
            t32_old is None,
            f"item={t32_old}",
        )
        abs_sh = c.request(
            "textDocument/signatureHelp",
            {"textDocument": {"uri": abs_uri}, "position": pos_at(abs_src, "abs(", after=True)},
        )
        abs_sh_label = ""
        abs_sigs = (abs_sh or {}).get("signatures") or []
        if abs_sigs:
            abs_sh_label = abs_sigs[0].get("label") or ""
        suite.check(
            "signature help abs genType",
            "abs" in abs_sh_label and "genType" in abs_sh_label,
            f"label={abs_sh_label!r}",
        )
        abs_locs = c.request(
            "textDocument/definition",
            {"textDocument": {"uri": abs_uri}, "position": pos_at(abs_src, "abs(", after=False)},
        )
        abs_def_uri = ""
        if isinstance(abs_locs, list) and abs_locs:
            abs_def_uri = (abs_locs[0].get("uri") or "").replace("\\", "/")
        suite.check(
            "definition abs in oge/misl/core",
            "oge/misl/core" in abs_def_uri.lower() and "builtin.misl" in abs_def_uri.lower(),
            f"locs={abs_locs}",
        )
        t32_locs = c.request(
            "textDocument/definition",
            {"textDocument": {"uri": abs_uri}, "position": pos_at(abs_src, "t32_2d =", after=False)},
        )
        t32_def_uri = ""
        if isinstance(t32_locs, list) and t32_locs:
            t32_def_uri = (t32_locs[0].get("uri") or "").replace("\\", "/")
        suite.check(
            "definition t32_2d in oge/misl/core",
            "oge/misl/core" in t32_def_uri.lower() and "builtin.misl" in t32_def_uri.lower(),
            f"locs={t32_locs}",
        )
        printf_def_src = (
            'import "core:debug"\n'
            "f :: proc() {\n"
            '\tdebug.printf("hi\\n")\n'
            "}\n"
        )
        printf_def_uri_doc = path_uri(REPO / "tmp_printf_def.misl")
        open_doc(c, printf_def_uri_doc, printf_def_src, 1)
        printf_locs = c.request(
            "textDocument/definition",
            {
                "textDocument": {"uri": printf_def_uri_doc},
                "position": pos_at(printf_def_src, "printf", after=False),
            },
        )
        printf_def_uri = ""
        if isinstance(printf_locs, list) and printf_locs:
            printf_def_uri = (printf_locs[0].get("uri") or "").replace("\\", "/")
        suite.check(
            "definition printf in oge/misl/core/debug.misl",
            "oge/misl/core" in printf_def_uri.lower() and "debug.misl" in printf_def_uri.lower(),
            f"locs={printf_locs}",
        )

        print("\n== core builtin.misl @builtin ==")
        builtin_path = REPO / "oge" / "misl" / "core" / "builtin.misl"
        if not builtin_path.exists():
            suite.check("core builtin.misl exists", False, str(builtin_path))
        else:
            core_client = make_client(exe)
            try:
                user_uri = path_uri(REPO / "tmp_core_dir_user.misl")
                user_src = MINIMAL_STRUCT + (
                    "Data :: struct #align(16) { color: [4]f32 }\n"
                    "VS_Out :: struct { pos: [4]f32 | SV_Position }\n"
                    "vs :: proc \"vertex\"(data: ^Data | SV_Data, vertex_id: u32 | SV_Vertex) -> (out: VS_Out) {\n"
                    "\t_ = data\n"
                    "\t_ = vertex_id\n"
                    "\tout.pos = [4]f32{0, 0, 0, 1}\n"
                    "\treturn out\n"
                    "}\n"
                )
                open_doc(core_client, user_uri, user_src, 1)
                builtin_uri = path_uri(builtin_path)
                builtin_text = builtin_path.read_text(encoding="utf-8")
                core_client.drain_diags()
                open_doc(core_client, builtin_uri, builtin_text, 1)
                time.sleep(0.25)
                msgs = core_client.drain_diags()
                deadline = time.time() + 2.0
                while time.time() < deadline and not msgs:
                    time.sleep(0.05)
                    msgs.extend(core_client.drain_diags())
                time.sleep(0.1)
                msgs.extend(core_client.drain_diags())
                texts = []
                for m in msgs:
                    params = m.get("params") or {}
                    diag_uri = (params.get("uri") or "").replace("\\", "/").lower()
                    if "builtin.misl" in diag_uri:
                        for d in params.get("diagnostics") or []:
                            texts.append(d.get("message") or "")
                banned = "only allowed in compiler-integrated"
                suite.check(
                    "core builtin.misl has no @builtin errors",
                    all(banned not in t for t in texts),
                    f"diags={texts}",
                )
                user_syms = core_client.request(
                    "textDocument/documentSymbol",
                    {"textDocument": {"uri": user_uri}},
                )
                user_names = {s.get("name") for s in (user_syms or [])}
                suite.check(
                    "user file symbols while core builtin.misl is open",
                    {"S", "E", "f"} <= user_names,
                    f"names={sorted(user_names)}",
                )
                user_lenses = core_client.request(
                    "textDocument/codeLens",
                    {"textDocument": {"uri": user_uri}},
                )
                suite.check(
                    "user file codeLens while core builtin.misl is open",
                    isinstance(user_lenses, list)
                    and any((l.get("command") or {}).get("command") == "misl.showSpirv" for l in user_lenses),
                    f"lenses={user_lenses}",
                )
            except Exception as e:
                suite.check("core builtin.misl session", False, str(e))
            finally:
                core_client.close()

        # ========== Inlay hints ==========
        print("\n== inlay hints ==")
        inlay_src = (
            "S :: struct { x: i32, y: i32 }\n"
            "sum :: proc(left: i32, right: i32) -> i32 { return left + right }\n"
            "f :: proc(right: i32) {\n"
            "\t_ = sum(1, right)\n"
            "\t_ = S{1, 2}\n"
            "}\n"
        )
        inlay_uri = path_uri(REPO / "tmp_inlays.misl")
        open_doc(c, inlay_uri, inlay_src, 1)
        inlays = c.request(
            "textDocument/inlayHint",
            {
                "textDocument": {"uri": inlay_uri},
                "range": {"start": {"line": 0, "character": 0}, "end": end_pos(inlay_src)},
            },
        )
        inlay_labels = {hint.get("label") for hint in (inlays or [])}
        suite.check(
            "inlay parameter and struct labels",
            {"left:", "right:", "x:", "y:"} <= inlay_labels,
            f"labels={sorted(inlay_labels)}",
        )

        # Same-name idents still get labels: light_attenuation(light, world, ...)
        same_src = (
            "Light :: struct { x: f32 }\n"
            "light_attenuation :: proc(light: Light, world: [2]f32, visibility_cookie: b32) -> f32 {\n"
            "\treturn 1\n"
            "}\n"
            "f :: proc(light: Light, world: [2]f32) {\n"
            "\t_ = light_attenuation(light, world, false)\n"
            "}\n"
        )
        same_uri = path_uri(REPO / "tmp_inlay_same_name.misl")
        open_doc(c, same_uri, same_src, 1)
        time.sleep(0.08)
        same_inlays = c.request(
            "textDocument/inlayHint",
            {
                "textDocument": {"uri": same_uri},
                "range": {"start": {"line": 0, "character": 0}, "end": end_pos(same_src)},
            },
        )
        same_labels = {hint.get("label") for hint in (same_inlays or [])}
        suite.check(
            "inlay labels when arg ident matches param",
            {"light:", "world:", "visibility_cookie:"} <= same_labels,
            f"labels={sorted(same_labels)}",
        )

        # Compound assign (`+=` / `-=`) must not shift param hints into the callee
        # or into the middle of the first argument (`data.samp:lamps`).
        assign_src = (
            "vec2 :: [2]f32\n"
            "Data :: struct #align(16) { lamps: t32_2d, lamps_sampler: s32 }\n"
            "VS_Out :: struct { pos: [4]f32 | SV_Position }\n"
            'vs :: proc "vertex"(data: ^Data | SV_Data) -> (out: VS_Out) {\n'
            "\tc := sample(data.lamps, data.lamps_sampler, vec2(0, 0))\n"
            "\tc += sample(data.lamps, data.lamps_sampler, vec2(0, 0))\n"
            "\tc -= sample(data.lamps, data.lamps_sampler, vec2(0, 0))\n"
            "\tc = c + sample(data.lamps, data.lamps_sampler, vec2(0, 0))\n"
            "\tout.pos = c\n"
            "\treturn out\n"
            "}\n"
        )
        assign_uri = path_uri(REPO / "tmp_inlay_assign.misl")
        open_doc(c, assign_uri, assign_src, 1)
        time.sleep(0.08)
        assign_inlays = c.request(
            "textDocument/inlayHint",
            {
                "textDocument": {"uri": assign_uri},
                "range": {"start": {"line": 0, "character": 0}, "end": end_pos(assign_src)},
            },
        )
        assign_lines = assign_src.split("\n")
        for line_i, line_text in enumerate(assign_lines):
            if "sample(" not in line_text:
                continue
            sample_at = line_text.find("sample(")
            first_data = line_text.find("data.lamps", sample_at)
            second_data = line_text.find("data.lamps", first_data + 1)
            on_line = [
                h for h in (assign_inlays or [])
                if h.get("position", {}).get("line") == line_i
            ]
            tex_cols = sorted(
                h["position"]["character"] for h in on_line if h.get("label") == "tex:"
            )
            samp_cols = sorted(
                h["position"]["character"] for h in on_line if h.get("label") == "samp:"
            )
            kind = line_text.strip()[:4]
            suite.check(
                f"inlay {kind!r} tex at first arg (not before sample)",
                tex_cols == [first_data],
                f"tex_cols={tex_cols} want={[first_data]} sample_at={sample_at} line={line_text!r}",
            )
            suite.check(
                f"inlay {kind!r} samp at second arg (not inside data.lamps)",
                samp_cols == [second_data],
                f"samp_cols={samp_cols} want={[second_data]} mid={first_data + len('data.')} line={line_text!r}",
            )

        # ========== misl.lsp.json feature gating ==========
        print("\n== misl.lsp.json ==")
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            cfg = {
                "server_path": "",
                "collections": [],
                "features": {
                    "hover": True,
                    "definition": True,
                    "type_definition": True,
                    "references": True,
                    "document_highlight": True,
                    "document_symbol": True,
                    "workspace_symbol": True,
                    "rename": True,
                    "completion": True,
                    "signature_help": True,
                    "semantic_tokens": True,
                    "inlay_hints": False,
                    "code_actions": True,
                    "code_lens": True,
                    "fmag_preview": True,
                    "spirv_preview": True,
                },
            }
            (tmp_path / "misl.lsp.json").write_text(json.dumps(cfg), encoding="utf-8")
            src_path = tmp_path / "gate.misl"
            src_path.write_text(inlay_src, encoding="utf-8")
            cfg_client = make_client(exe, root=tmp_path)
            try:
                gate_uri = path_uri(src_path)
                open_doc(cfg_client, gate_uri, inlay_src, 1)
                gated = cfg_client.request(
                    "textDocument/inlayHint",
                    {
                        "textDocument": {"uri": gate_uri},
                        "range": {"start": {"line": 0, "character": 0}, "end": end_pos(inlay_src)},
                    },
                )
                suite.check(
                    "inlay_hints false returns no hints",
                    gated is None or gated == [],
                    f"hints={gated}",
                )
                # Hot-enable via watched file change
                cfg["features"]["inlay_hints"] = True
                (tmp_path / "misl.lsp.json").write_text(json.dumps(cfg), encoding="utf-8")
                cfg_client.notify(
                    "workspace/didChangeWatchedFiles",
                    {
                        "changes": [
                            {
                                "uri": path_uri(tmp_path / "misl.lsp.json"),
                                "type": 2,
                            }
                        ]
                    },
                )
                time.sleep(0.15)
                enabled = cfg_client.request(
                    "textDocument/inlayHint",
                    {
                        "textDocument": {"uri": gate_uri},
                        "range": {"start": {"line": 0, "character": 0}, "end": end_pos(inlay_src)},
                    },
                )
                enabled_labels = {hint.get("label") for hint in (enabled or [])}
                suite.check(
                    "inlay_hints true after didChangeWatchedFiles",
                    {"left:", "x:", "y:"} <= enabled_labels,
                    f"labels={sorted(enabled_labels)}",
                )
            finally:
                cfg_client.close()

        # ========== Document symbols ==========
        print("\n== document symbols ==")
        change_doc(c, uri, MINIMAL_STRUCT, ver + 1)
        ver += 1
        syms = c.request("textDocument/documentSymbol", {"textDocument": {"uri": uri}})
        names = set()
        def walk(ss):
            for s in ss or []:
                names.add(s.get("name"))
                walk(s.get("children") or [])
        walk(syms)
        suite.check("symbols contain S,E,f", {"S", "E", "f"} <= names, f"names={sorted(names)}")
        by_name = {s.get("name"): s for s in (syms or [])}
        s_children = {s.get("name") for s in (by_name.get("S", {}).get("children") or [])}
        e_children = {s.get("name") for s in (by_name.get("E", {}).get("children") or [])}
        suite.check(
            "symbols nest fields and enum members",
            {"x", "y"} <= s_children and {"A", "B", "C"} <= e_children,
            f"S={sorted(s_children)} E={sorted(e_children)}",
        )
        import_path = REPO / "oge" / "misl" / "test" / "import_rel.misl"
        import_uri = path_uri(import_path)
        open_doc(c, import_uri, import_path.read_text(encoding="utf-8"), 1)
        workspace_syms = c.request("workspace/symbol", {"query": "double"})
        suite.check(
            "workspace symbols include unopened imports",
            any(
                sym.get("name") == "double"
                and "import_deps/common.misl" in (sym.get("location") or {}).get("uri", "")
                for sym in (workspace_syms or [])
            ),
            f"symbols={workspace_syms}",
        )

        # ========== Code actions ==========
        print("\n== code actions ==")
        switch_src = (
            "E :: enum u32 { A, B, C }\n"
            "f :: proc(e: E) {\n"
            "\tswitch e {\n"
            "\tcase .A:\n"
            "\t}\n"
            "}\n"
        )
        switch_uri = path_uri(REPO / "tmp_switch_action.misl")
        open_doc(c, switch_uri, switch_src, 1)
        switch_pos = pos_at(switch_src, "switch e", after=False)
        actions = c.request(
            "textDocument/codeAction",
            {
                "textDocument": {"uri": switch_uri},
                "range": {"start": switch_pos, "end": switch_pos},
                "context": {"diagnostics": []},
            },
        )
        fill_action = next(
            (action for action in (actions or []) if action.get("title") == "Fill missing enum switch cases"),
            None,
        )
        fill_text = ""
        if fill_action:
            changes = ((fill_action.get("edit") or {}).get("documentChanges") or [])
            fill_text = "".join(
                edit.get("newText") or ""
                for change in changes
                for edit in (change.get("edits") or [])
            )
        suite.check(
            "code action fills missing enum cases",
            fill_action is not None and "case .B:" in fill_text and "case .C:" in fill_text,
            f"actions={actions}",
        )

        which_src = (
            "E :: enum u32 { A, B, C }\n"
            "K :: E.A\n"
            "which K {\n"
            "case .A:\n"
            "}\n"
        )
        which_uri = path_uri(REPO / "tmp_which_action.misl")
        open_doc(c, which_uri, which_src, 1)
        which_pos = pos_at(which_src, "which K", after=False)
        which_actions = c.request(
            "textDocument/codeAction",
            {
                "textDocument": {"uri": which_uri},
                "range": {"start": which_pos, "end": which_pos},
                "context": {"diagnostics": []},
            },
        )
        which_fill = next(
            (action for action in (which_actions or []) if action.get("title") == "Fill missing enum which cases"),
            None,
        )
        which_fill_text = ""
        if which_fill:
            changes = ((which_fill.get("edit") or {}).get("documentChanges") or [])
            which_fill_text = "".join(
                edit.get("newText") or ""
                for change in changes
                for edit in (change.get("edits") or [])
            )
        suite.check(
            "code action fills missing enum which cases",
            which_fill is not None and "case .B:" in which_fill_text and "case .C:" in which_fill_text,
            f"actions={which_actions}",
        )

        partial_src = (
            "package main\n"
            "E :: enum { A, B, C }\n"
            "f :: proc(e: E) {\n"
            "\t#partial switch e {\n"
            "\tcase .A:\n"
            "\t}\n"
            "}\n"
        )
        change_doc(c, switch_uri, partial_src, 2)
        partial_pos = pos_at(partial_src, "#partial switch", after=False)
        partial_actions = c.request(
            "textDocument/codeAction",
            {
                "textDocument": {"uri": switch_uri},
                "range": {"start": partial_pos, "end": partial_pos},
                "context": {"diagnostics": []},
            },
        )
        suite.check(
            "partial switch has no fill action",
            not any((a.get("title") == "Fill missing enum switch cases") for a in (partial_actions or [])),
            f"actions={partial_actions}",
        )

        # ========== CodeLens + SPIR-V preview ==========
        print("\n== codeLens / spirv preview ==")
        lens_src = (
            "Data :: struct #align(16) { color: [4]f32 }\n"
            "VS_Out :: struct { pos: [4]f32 | SV_Position }\n"
            "vs :: proc \"vertex\"(data: ^Data | SV_Data, vertex_id: u32 | SV_Vertex) -> (out: VS_Out) {\n"
            "\t_ = data\n"
            "\t_ = vertex_id\n"
            "\tout.pos = [4]f32{0, 0, 0, 1}\n"
            "\treturn out\n"
            "}\n"
        )
        change_doc(c, uri, lens_src, ver + 1)
        ver += 1
        lenses = c.request("textDocument/codeLens", {"textDocument": {"uri": uri}})
        suite.check("codeLens nonempty", isinstance(lenses, list) and len(lenses) >= 1, f"lenses={lenses}")
        if lenses:
            cmd = (lenses[0].get("command") or {})
            args = cmd.get("arguments") or []
            suite.check("codeLens command misl.showSpirv", cmd.get("command") == "misl.showSpirv", f"cmd={cmd}")
            if len(args) >= 2:
                try:
                    prev = c.request("misl/spirvPreview", {"uri": uri, "entity": args[1]})
                    suite.check(
                        "spirvPreview returns text",
                        isinstance(prev, dict) and isinstance(prev.get("spirv"), str) and len(prev["spirv"]) > 0,
                        f"prev_keys={list(prev) if isinstance(prev, dict) else prev}",
                    )
                    prev2 = c.request("misl/spirvPreview", {"uri": uri, "entity": args[1]})
                    suite.check(
                        "spirvPreview second call ok",
                        isinstance(prev2, dict) and len(prev2.get("spirv") or "") > 0,
                        f"prev2={prev2!r}"[:200],
                    )
                    prev3 = c.request("misl/spirvPreview", {"uri": uri, "entity": args[1]})
                    suite.check(
                        "spirvPreview third call ok",
                        isinstance(prev3, dict) and len(prev3.get("spirv") or "") > 0,
                        f"prev3={prev3!r}"[:200],
                    )
                except Exception as e:
                    suite.check("spirvPreview", False, str(e))

        # ========== main.misl excerpt (real file path) ==========
        print("\n== real main.misl excerpt soft edits ==")
        main_path = REPO / "data" / "shader" / "main.misl"
        if main_path.exists():
            main_uri = path_uri(main_path)
            main_text = main_path.read_text(encoding="utf-8")
            open_doc(c, main_uri, main_text, 1)
            time.sleep(0.2)
            # Typing incomplete bit_set near L151 must not trap the server
            lines = main_text.splitlines(keepends=True)
            if len(lines) >= 151:
                prefix = "".join(lines[:150])
                suffix = "".join(lines[150:])
                for partial in ("Flags :: bit_set[", "Flags :: bit_set[Mask_Type; u32]"):
                    change_doc(c, main_uri, prefix + partial + "\n" + suffix, ver + 1)
                    ver += 1
                    time.sleep(0.05)
                    if c.proc.poll() is not None:
                        suite.check("alive typing bit_set[", False, f"exit={c.proc.returncode} at {partial!r}")
                        break
                else:
                    suite.check("alive typing bit_set[", True)
            # Unique to sprite_fs (not other fragment_in uses)
            old = "\tout = sample(fragment_in.texture, fragment_in.sampler, fragment_in.uv)\n"
            new = "\tout = sample(fragment_in., fragment_in.sampler, fragment_in.uv)\n"
            if old not in main_text:
                suite.check("main.misl sprite_fs anchor", False, "expected fragment_in.texture sample pattern missing")
            else:
                broken = main_text.replace(old, new, 1)
                change_doc(c, main_uri, broken, 2)
                time.sleep(0.15)
                suite.check("alive after main.misl fragment_in.", c.proc.poll() is None, f"exit={c.proc.returncode}")
                caret = pos_at(broken, "sample(fragment_in.")
                items = complete(c, main_uri, caret, ".")
                suite.expect_labels(
                    "main.misl fragment_in. fields",
                    items,
                    {"uv", "texture", "sampler", "pos"},
                )

            # Typing `name:` before an existing `:=` must not crash (incomplete type annotation).
            change_doc(c, main_uri, main_text, ver + 1)
            ver += 1
            time.sleep(0.1)
            mask_anchor = "sprite_fs :: proc"
            ob = main_text.find("{", main_text.find(mask_anchor))
            if ob < 0:
                suite.check("main.misl mask_fs body", False, "open brace missing")
            else:
                typed = main_text[: ob + 1] + "\n\tx:" + main_text[ob + 1 :]
                change_doc(c, main_uri, typed, ver + 1)
                ver += 1
                time.sleep(0.15)
                suite.check("alive after typing local name:", c.proc.poll() is None, f"exit={c.proc.returncode}")
                if c.proc.poll() is None:
                    try:
                        c.request(
                            "textDocument/documentSymbol",
                            {"textDocument": {"uri": main_uri}},
                            timeout=3,
                        )
                        suite.check("symbols after local name:", True)
                    except Exception as e:
                        suite.check("symbols after local name:", False, str(e))
                    try:
                        c.request(
                            "textDocument/semanticTokens/full",
                            {"textDocument": {"uri": main_uri}},
                            timeout=3,
                        )
                        suite.check("semanticTokens after local name:", True)
                    except Exception as e:
                        suite.check("semanticTokens after local name:", False, str(e))
        else:
            suite.check("main.misl exists", False, str(main_path))

        # bit_set elem type must appear in semantic tokens (Mask_Type highlight)
        print("\n== bit_set semantic tokens ==")
        bitset_src = (
            "package main\n"
            "Mask_Type :: enum u32 { A, B }\n"
            "Masks :: bit_set[Mask_Type; u32]\n"
        )
        bitset_uri = path_uri(REPO / "tmp_bitset_tokens.misl")
        open_doc(c, bitset_uri, bitset_src, 1)
        time.sleep(0.1)
        try:
            toks = c.request(
                "textDocument/semanticTokens/full",
                {"textDocument": {"uri": bitset_uri}},
                timeout=3,
            )
            data = (toks or {}).get("data") or []
            needle = "bit_set[Mask_Type"
            abs_off = bitset_src.find(needle)
            suite.check("bitset source has Mask_Type", abs_off >= 0)
            if abs_off >= 0:
                target = abs_off + len("bit_set[")
                line = bitset_src.count("\n", 0, target)
                col = target - (bitset_src.rfind("\n", 0, target) + 1)
                hit = False
                pl = pc = 0
                for i in range(0, len(data) - 4, 5):
                    pl += data[i]
                    pc = data[i + 1] if data[i] != 0 else pc + data[i + 1]
                    length = data[i + 2]
                    if pl == line and pc <= col < pc + length:
                        hit = True
                        break
                suite.check("Mask_Type in bit_set has semantic token", hit, f"line={line} col={col} n={len(data)//5}")
        except Exception as e:
            suite.check("bit_set semantic tokens", False, str(e))

        print("\n== rune literal semantic tokens ==")
        rune_src = "ch :: 'A'\n"
        rune_uri = path_uri(REPO / "tmp_rune_tokens.misl")
        open_doc(c, rune_uri, rune_src, 1)
        time.sleep(0.1)
        try:
            toks = c.request(
                "textDocument/semanticTokens/full",
                {"textDocument": {"uri": rune_uri}},
                timeout=3,
            )
            data = (toks or {}).get("data") or []
            abs_off = rune_src.find("'A'")
            suite.check("rune source has 'A'", abs_off >= 0)
            legend = (
                ((caps.get("semanticTokensProvider") or {}).get("legend") or {}).get("tokenTypes")
                or []
            )
            string_idx = legend.index("string") if "string" in legend else -1
            line = rune_src.count("\n", 0, abs_off)
            col = abs_off - (rune_src.rfind("\n", 0, abs_off) + 1)
            hit_type = None
            pl = pc = 0
            for i in range(0, len(data) - 4, 5):
                pl += data[i]
                pc = data[i + 1] if data[i] != 0 else pc + data[i + 1]
                length = data[i + 2]
                tok_type = data[i + 3]
                if pl == line and pc <= col < pc + length:
                    hit_type = tok_type
                    break
            suite.check(
                "character literal has string semantic token",
                hit_type == string_idx,
                f"hit_type={hit_type} string_idx={string_idx} legend={legend} n={len(data)//5}",
            )
        except Exception as e:
            suite.check("rune literal semantic tokens", False, str(e))

        print("\n== 0h float semantic tokens ==")
        hexf_src = "x :: 0h3F800000\n"
        hexf_uri = path_uri(REPO / "tmp_hexfloat_tokens.misl")
        open_doc(c, hexf_uri, hexf_src, 1)
        time.sleep(0.1)
        try:
            toks = c.request(
                "textDocument/semanticTokens/full",
                {"textDocument": {"uri": hexf_uri}},
                timeout=3,
            )
            data = (toks or {}).get("data") or []
            legend = (
                ((caps.get("semanticTokensProvider") or {}).get("legend") or {}).get("tokenTypes")
                or []
            )
            number_idx = legend.index("number") if "number" in legend else -1
            hexf_off = hexf_src.find("0h3F800000")
            suite.check("0h source has literal", hexf_off >= 0)
            hit = semantic_token_type_at(hexf_src, data, hexf_off)
            mid = semantic_token_type_at(hexf_src, data, hexf_off + 4)
            suite.check(
                "0h literal has number semantic token",
                hit == number_idx and mid == number_idx,
                f"hit={hit} mid={mid} number_idx={number_idx} legend={legend} n={len(data)//5}",
            )
        except Exception as e:
            suite.check("0h float semantic tokens", False, str(e))

        # ========== Switch / new-feature soft edits (must not trap server) ==========
        print("\n== switch / new-feature typing ==")
        feat_uri = path_uri(REPO / "tmp_switch_features.misl")
        feat_prefix = (
            "package main\n"
            "E :: enum u32 { A, B }\n"
            'vs :: proc "vertex"(vid: u32 | SV_Vertex) -> (out: [4]f32 | SV_Position) {\n'
            "\tflag := true\n"
            "\te: E = .A\n"
        )
        feat_suffix = "\treturn out\n}\n"
        open_doc(c, feat_uri, feat_prefix + feat_suffix, 1)
        ver_feat = 1
        switch_steps = []
        built = "\t"
        for ch in "switch":
            built += ch
            switch_steps.append(built + "\n")
        switch_steps += [
            "\tswitch {\n",
            "\tswitch {\n\tcase true:\n",
            "\tswitch {\n\tcase true:\n\t\tflag &&= false\n\t}\n",
            "\tswitch e {\n\tcase .A:\n\t}\n",
            "\twhich e {\n",
            "\twhich e {\n\tcase .A:\n",
            "\twhich e {\n\tcase .A:\n\t}\n",
            "\tflag &&=\n",
            "\treturn\n",
        ]
        for snip in switch_steps:
            ver_feat += 1
            change_doc(c, feat_uri, feat_prefix + snip + feat_suffix, ver_feat)
            time.sleep(0.03)
            if c.proc.poll() is not None:
                suite.check("alive typing switch/features", False, f"exit={c.proc.returncode} at {snip!r}")
                break
            try:
                c.request("textDocument/codeAction", {
                    "textDocument": {"uri": feat_uri},
                    "range": {"start": {"line": 3, "character": 0}, "end": {"line": 3, "character": 1}},
                    "context": {"diagnostics": []},
                }, timeout=3)
                c.request("textDocument/semanticTokens/full", {"textDocument": {"uri": feat_uri}}, timeout=3)
            except Exception:
                pass
            if c.proc.poll() is not None:
                suite.check("alive typing switch/features", False, f"exit={c.proc.returncode} after requests at {snip!r}")
                break
        else:
            suite.check("alive typing switch/features", True)

        # Orphan module-level return (brace mismatch residue) must not assert-crash
        orphan_uri = path_uri(REPO / "tmp_orphan_return.misl")
        open_doc(c, orphan_uri, "return 0\n", 1)
        time.sleep(0.1)
        suite.check("alive after module-level return", c.proc.poll() is None, f"exit={c.proc.returncode}")

        # ========== Semantic (`| SV_*`) completions ==========
        print("\n== semantic | completions ==")
        sem_cases = [
            (
                "struct field |",
                "package main\nS :: struct {\n\tpos: [4]f32 |\n}\n",
                "f32 |",
                {"SV_Position", "SV_Target"},
                {"SV_Data", "SV_Vertex"},
            ),
            (
                "vertex param |",
                'package main\nvs :: proc "vertex"(data: ^i32 |) -> (out: [4]f32) {\n\treturn out\n}\n',
                "^i32 |",
                {"SV_Data", "SV_Indirect_Data", "SV_Vertex", "SV_Instance"},
                {"SV_Target"},
            ),
            (
                "fragment result |",
                'package main\nfs :: proc "fragment"(x: i32) -> (out: [4]f32 |) {\n\treturn out\n}\n',
                "f32 |",
                {"SV_Target", "SV_Position"},
                {"SV_Data", "SV_Vertex"},
            ),
            (
                "compute param |",
                'package main\ncs :: proc "compute"(gid: [3]u32 |) {\n}\n',
                "u32 |",
                {"SV_Data", "SV_Global_Thread", "SV_Group_Index"},
                {"SV_Target", "SV_Position"},
            ),
            (
                "fmag param |",
                'package main\nshade :: proc "fmag"(x: f32 |) -> f32 {\n\treturn x\n}\n',
                "f32 |",
                set(),
                {"SV_Position", "SV_Target", "SV_Data", "SV_Vertex"},
            ),
        ]
        for name, src, needle, want, ban in sem_cases:
            sem_uri = path_uri(REPO / f"tmp_sem_{name.replace(' ', '_')}.misl")
            open_doc(c, sem_uri, src, 1)
            time.sleep(0.08)
            idx = src.find(needle) + len(needle)
            line = src.count("\n", 0, idx)
            col = idx - (src.rfind("\n", 0, idx) + 1)
            items = complete(c, sem_uri, {"line": line, "character": col}, "|")
            labs = {i.get("label") for i in items}
            suite.expect_labels(name, items, want)
            suite.check(f"{name} excludes other stage", labs.isdisjoint(ban), f"labs={sorted(labs)}")

        prefix_src = "package main\nS :: struct {\n\tpos: [4]f32 | SV\n}\n"
        prefix_uri = path_uri(REPO / "tmp_sem_prefix.misl")
        open_doc(c, prefix_uri, prefix_src, 1)
        time.sleep(0.08)
        idx = prefix_src.find("| SV") + len("| SV")
        line = prefix_src.count("\n", 0, idx)
        col = idx - (prefix_src.rfind("\n", 0, idx) + 1)
        items = complete(c, prefix_uri, {"line": line, "character": col}, None)
        suite.expect_labels("prefix SV filters", items, {"SV_Position", "SV_Target"})

    finally:
        try:
            c.close()
        except Exception:
            pass

    print("\n========== SUMMARY ==========")
    print(f"passed: {suite.passes}")
    print(f"failed: {len(suite.fails)}")
    for f in suite.fails:
        print(f"  - {f.name}: {f.detail}")
    return 1 if suite.fails else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    here = Path(__file__).resolve()
    repo = here.parents[5]
    if not (repo / "oge" / "misl").exists():
        p = here
        while p.parent != p:
            if (p / "oge" / "misl").exists():
                repo = p
                break
            p = p.parent
    ap.add_argument("--exe", type=Path, default=repo / "misl_lsp.exe")
    args = ap.parse_args()
    exe = args.exe if args.exe.is_absolute() else repo / args.exe
    # Bind repo for helpers that use module-level REPO
    global REPO
    REPO = repo
    if not exe.exists():
        print(f"missing server: {exe}", file=sys.stderr)
        return 2
    return run_tests(exe)


if __name__ == "__main__":
    sys.exit(main())
