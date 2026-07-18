"""Minimal stdlib HTTP client for local Ollama. chat() always sends
keep_alive=0 so the ~21 GB digest model unloads the moment a run ends —
the spec's zero-idle-RAM requirement lives on this line."""
from __future__ import annotations

import json
import urllib.error
import urllib.request

EMBED_BATCH = 32
DEFAULT_NUM_CTX = 32768


class OllamaError(RuntimeError):
    """Ollama unreachable or returned an unusable response."""


def _post(url: str, payload: dict, timeout: float) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except (urllib.error.URLError, TimeoutError) as e:
        raise OllamaError(f"ollama request failed at {url}: {e}") from e


def embed(texts: list[str], model: str, base_url: str,
          timeout: float = 120.0) -> list[list[float]]:
    out: list[list[float]] = []
    for i in range(0, len(texts), EMBED_BATCH):
        batch = texts[i:i + EMBED_BATCH]
        data = _post(f"{base_url}/api/embed",
                     {"model": model, "input": batch}, timeout)
        embs = data.get("embeddings") or []
        if len(embs) != len(batch):
            raise OllamaError(
                f"embed returned {len(embs)} vectors for {len(batch)} inputs")
        out.extend(embs)
    return out


def chat(prompt: str, model: str, base_url: str, system: str | None = None,
         num_ctx: int = DEFAULT_NUM_CTX, timeout: float = 900.0) -> str:
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    data = _post(f"{base_url}/api/chat", {
        "model": model,
        "messages": messages,
        "stream": False,
        "keep_alive": 0,
        "options": {"num_ctx": num_ctx},
    }, timeout)
    content = (data.get("message") or {}).get("content", "").strip()
    if not content:
        raise OllamaError(f"empty reply from {model}")
    return content
