#!/usr/bin/env python3
"""Open full main.misl and hit heavy LSP requests."""
from __future__ import annotations
import os, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lsp_deep_test import Client, path_uri  # type: ignore
import subprocess

REPO = Path(__file__).resolve().parents[5]
EXE = REPO / "misl_lsp.exe"
MAIN = REPO / "data" / "shader" / "main.misl"

def main() -> None:
    text = MAIN.read_text(encoding="utf-8")
    uri = path_uri(MAIN)
    proc = subprocess.Popen(
        [str(EXE)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=str(REPO),
    )
    c = Client(proc=proc)
    c.start_reader()
    try:
        c.request("initialize", {
            "processId": os.getpid(),
            "rootUri": path_uri(REPO),
            "capabilities": {},
            "initializationOptions": {},
        })
        c.notify("initialized", {})
        c.notify("textDocument/didOpen", {
            "textDocument": {"uri": uri, "languageId": "misl", "version": 1, "text": text},
        })
        time.sleep(0.4)
        assert c.proc.poll() is None, f"died after open code={c.proc.returncode}"
        end = {"line": text.count("\n"), "character": 0}
        for method, params in [
            ("textDocument/documentSymbol", {"textDocument": {"uri": uri}}),
            ("textDocument/semanticTokens/full", {"textDocument": {"uri": uri}}),
            ("textDocument/inlayHint", {"textDocument": {"uri": uri}, "range": {"start": {"line": 0, "character": 0}, "end": end}}),
            ("textDocument/documentLink", {"textDocument": {"uri": uri}}),
            ("textDocument/codeLens", {"textDocument": {"uri": uri}}),
            ("textDocument/codeAction", {"textDocument": {"uri": uri}, "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}}, "context": {"diagnostics": []}}),
            ("workspace/symbol", {"query": "sprite"}),
        ]:
            c.request(method, params, timeout=20.0)
            assert c.proc.poll() is None, f"died after {method} code={c.proc.returncode}"
            print("ok", method)
        print("PASS")
    finally:
        c.close()

if __name__ == "__main__":
    main()
