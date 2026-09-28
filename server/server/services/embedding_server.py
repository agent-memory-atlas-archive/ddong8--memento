"""Standalone embedding HTTP server — runs on host machine, called by API container.

Usage:
  python -m server.services.embedding_server [--port 8002] [--model BAAI/bge-m3]

Provides a single endpoint:
  POST /embed  {"texts": ["hello", "world"]}  →  {"embeddings": [[...], [...]]}
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import threading
from contextlib import contextmanager
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
logger = logging.getLogger("embedding_server")

_model = None
# PyTorch MPS backend is NOT thread-safe — concurrent encode() calls segfault,
# so inference is serialized. Bulk requests go a few texts at a time and a
# short request (a search query) goes ahead of the next slice, instead of
# waiting behind a whole ingest batch.
URGENT_MAX_TEXTS = 2
URGENT_MAX_CHARS = 2000
BULK_SLICE = 1


class _Gate:
    """One encode at a time; urgent callers go before waiting bulk slices."""

    def __init__(self) -> None:
        self._cond = threading.Condition()
        self._busy = False
        self._urgent_waiting = 0

    @contextmanager
    def hold(self, urgent: bool):
        with self._cond:
            if urgent:
                self._urgent_waiting += 1
            try:
                while self._busy or (not urgent and self._urgent_waiting):
                    self._cond.wait()
            finally:
                if urgent:
                    self._urgent_waiting -= 1
            self._busy = True
        try:
            yield
        finally:
            with self._cond:
                self._busy = False
                self._cond.notify_all()


class _Turns:
    """First come, first served across bulk requests: a bulk request keeps its
    turn for all of its slices (so concurrent ingest batches finish one after
    another, as before, instead of all crawling along together and timing
    out), while urgent requests still slip in between slices via _Gate."""

    def __init__(self) -> None:
        self._cond = threading.Condition()
        self._next_ticket = 0
        self._serving = 0

    @contextmanager
    def turn(self):
        with self._cond:
            ticket = self._next_ticket
            self._next_ticket += 1
            while ticket != self._serving:
                self._cond.wait()
        try:
            yield
        finally:
            with self._cond:
                self._serving += 1
                self._cond.notify_all()


_gate = _Gate()
_turns = _Turns()


def is_urgent(texts: list[str]) -> bool:
    return len(texts) <= URGENT_MAX_TEXTS and sum(len(t) for t in texts) <= URGENT_MAX_CHARS


def _encode_slices(texts: list[str], step: int, urgent: bool) -> list[list[float]]:
    out: list[list[float]] = []
    for i in range(0, len(texts), step):
        with _gate.hold(urgent):
            vectors = _model.encode(texts[i:i + step], normalize_embeddings=True, show_progress_bar=False)
        out.extend(v.tolist() for v in vectors)
    return out


def encode(texts: list[str]) -> list[list[float]]:
    if is_urgent(texts):
        return _encode_slices(texts, len(texts), urgent=True)
    with _turns.turn():
        return _encode_slices(texts, BULK_SLICE, urgent=False)

# BGE-M3 supports up to 8192 tokens. Roughly cap text at 32000 chars (~8k tokens).
MAX_TEXT_CHARS = 32000


def _load_model(model_name: str):
    global _model
    # Device selection:
    # - CUDA: real GPU, use it.
    # - MPS (Apple Silicon): reachable but hangs the process in STAT=U
    #   uninterruptible sleep within ~10min of idle inference, because the
    #   OS compresses BGE-M3 tensors into the unified-memory swap pool and
    #   the next Metal command buffer dispatch deadlocks waking them up.
    #   Confirmed empirically. Fall back to CPU until we move to ONNX/int8.
    # - CPU on M-series: ~200ms for 50 chunks via AMX/AVX, fully stable.
    # Override with MEMENTO_EMBEDDING_DEVICE if you want to gamble on MPS.
    import torch
    forced = os.environ.get("MEMENTO_EMBEDDING_DEVICE", "").strip().lower()
    if forced in ("cpu", "cuda", "mps"):
        device = forced
    elif torch.cuda.is_available():
        device = "cuda"
    else:
        device = "cpu"
    logger.info("Loading %s on %s ...", model_name, device)
    from sentence_transformers import SentenceTransformer
    _model = SentenceTransformer(model_name, device=device)
    logger.info("Model loaded: %s (dim=%d, device=%s)", model_name, _model.get_sentence_embedding_dimension(), device)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/embed":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            texts = body.get("texts", [])
            if not texts:
                self._json_response({"embeddings": []})
                return

            # Defensive: clip oversized inputs to avoid tokenizer / MPS crashes
            texts = [(t or "")[:MAX_TEXT_CHARS] for t in texts]

            self._json_response({"embeddings": encode(texts)})
        except Exception as e:
            logger.error("Error: %s", e)
            self.send_error(500, str(e))

    def do_GET(self):
        if self.path == "/health":
            self._json_response({"status": "ok", "model": _model is not None})
        else:
            self.send_error(404)

    def _json_response(self, data):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        logger.info(format, *args)


def main():
    parser = argparse.ArgumentParser(description="Embedding HTTP Server")
    parser.add_argument("--port", type=int, default=int(os.environ.get("MEMENTO_EMBEDDING_PORT", "8002")))
    parser.add_argument("--model", default=os.environ.get("MEMENTO_EMBEDDING_MODEL_NAME", "BAAI/bge-m3"))
    args = parser.parse_args()

    _load_model(args.model)

    class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
        allow_reuse_address = True
        daemon_threads = True

    server = ThreadedHTTPServer(("0.0.0.0", args.port), Handler)
    logger.info("Embedding server running on port %d", args.port)
    server.serve_forever()


if __name__ == "__main__":
    main()
