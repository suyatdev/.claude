from memsearch import digest
from memsearch.config import load_config
from memsearch.extract import SessionExtract
from tests.test_config import REAL_CONFIG


def make_extract(text="User: fix bug\n\nAssistant: fixed") -> SessionExtract:
    return SessionExtract("s1", "2026-07-01", "/Users/x/repo", text)


def test_truncate_middle_short_text_untouched():
    assert digest.truncate_middle("abc", 10) == "abc"


def test_truncate_middle_keeps_head_and_tail():
    text = "HEAD" + "x" * 1000 + "TAIL"
    out = digest.truncate_middle(text, 100)
    assert out.startswith("HEAD") and out.endswith("TAIL")
    assert "truncated" in out
    assert len(out) < 200


def test_build_prompt_has_sections_and_transcript():
    p = digest.build_prompt(make_extract(), 80_000)
    for section in ("## Summary", "## Decisions", "## Bugs & Fixes",
                    "## Files Touched"):
        assert section in p
    assert "fix bug" in p


def test_digest_session_calls_chat_with_config_model():
    cfg = load_config(REAL_CONFIG)
    calls = {}

    def fake_chat(prompt, model, base_url, system=None, **kw):
        calls.update(prompt=prompt, model=model, base_url=base_url, system=system)
        return "## Summary\nDid things."

    out = digest.digest_session(make_extract(), cfg, chat=fake_chat)
    assert out == "## Summary\nDid things."
    assert calls["model"] == cfg.digest_model
    assert calls["base_url"] == cfg.ollama_url
    assert calls["system"] == digest.DIGEST_SYSTEM
