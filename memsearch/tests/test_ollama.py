import pytest

from memsearch import ollama


class Recorder:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []

    def __call__(self, url, payload, timeout):
        self.calls.append((url, payload))
        return self.responses.pop(0)


def test_embed_batches_and_orders(monkeypatch):
    texts = [f"t{i}" for i in range(70)]  # 70 -> batches of 32, 32, 6
    rec = Recorder([
        {"embeddings": [[float(i)] for i in range(32)]},
        {"embeddings": [[float(i)] for i in range(32)]},
        {"embeddings": [[float(i)] for i in range(6)]},
    ])
    monkeypatch.setattr(ollama, "_post", rec)
    out = ollama.embed(texts, "m", "http://x")
    assert len(out) == 70
    assert len(rec.calls) == 3
    assert rec.calls[0][0] == "http://x/api/embed"
    assert rec.calls[0][1]["input"] == texts[:32]
    assert rec.calls[2][1]["input"] == texts[64:]


def test_embed_count_mismatch_raises(monkeypatch):
    rec = Recorder([{"embeddings": [[0.1]]}])
    monkeypatch.setattr(ollama, "_post", rec)
    with pytest.raises(ollama.OllamaError, match="1 vectors for 2"):
        ollama.embed(["a", "b"], "m", "http://x")


def test_chat_sends_keep_alive_zero_and_system(monkeypatch):
    rec = Recorder([{"message": {"content": "digest text"}}])
    monkeypatch.setattr(ollama, "_post", rec)
    out = ollama.chat("hello", "big-model", "http://x", system="be terse")
    assert out == "digest text"
    url, payload = rec.calls[0]
    assert url == "http://x/api/chat"
    assert payload["keep_alive"] == 0
    assert payload["stream"] is False
    assert payload["options"]["num_ctx"] == 32768
    assert payload["messages"][0] == {"role": "system", "content": "be terse"}
    assert payload["messages"][1] == {"role": "user", "content": "hello"}


def test_chat_empty_reply_raises(monkeypatch):
    rec = Recorder([{"message": {"content": ""}}])
    monkeypatch.setattr(ollama, "_post", rec)
    with pytest.raises(ollama.OllamaError, match="empty"):
        ollama.chat("hello", "m", "http://x")
