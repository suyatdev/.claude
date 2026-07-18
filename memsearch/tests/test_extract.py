import json
from pathlib import Path

from memsearch.extract import extract_session


def jl(**d) -> str:
    return json.dumps(d)


def write_session(tmp_path: Path, lines: list[str]) -> Path:
    p = tmp_path / "abc-123.jsonl"
    p.write_text("\n".join(lines) + "\n")
    return p


BASE = dict(cwd="/Users/x/repo", timestamp="2026-07-15T10:00:00.000Z",
            isSidechain=False)


def test_extracts_user_and_assistant_turns(tmp_path):
    p = write_session(tmp_path, [
        jl(type="custom-title", customTitle="t"),
        jl(type="user", message={"role": "user", "content":
           "Fix the login bug<system-reminder>noise</system-reminder>"}, **BASE),
        jl(type="assistant", message={"role": "assistant", "content": [
            {"type": "thinking", "thinking": "secret reasoning"},
            {"type": "text", "text": "Found it: the token check inverted."},
            {"type": "tool_use", "name": "Edit", "input": {"x": 1}},
        ]}, **BASE),
    ])
    ex = extract_session(p)
    assert ex is not None
    assert ex.session_id == "abc-123"
    assert ex.session_date == "2026-07-15"
    assert ex.cwd == "/Users/x/repo"
    assert "Fix the login bug" in ex.text
    assert "noise" not in ex.text
    assert "secret reasoning" not in ex.text
    assert "token check inverted" in ex.text
    assert "[tool: Edit]" in ex.text          # tool NAME kept as light signal
    assert '"input"' not in ex.text           # tool payload dropped


def test_drops_sidechain_meta_and_tool_results(tmp_path):
    side = dict(BASE, isSidechain=True)
    p = write_session(tmp_path, [
        jl(type="user", message={"role": "user", "content": "real question"}, **BASE),
        jl(type="user", message={"role": "user", "content": "sidechain text"}, **side),
        jl(type="user", isMeta=True,
           message={"role": "user", "content": "meta noise"}, **BASE),
        jl(type="user", message={"role": "user", "content": [
            {"type": "tool_result", "content": "huge file dump"}]}, **BASE),
        jl(type="assistant", message={"role": "assistant", "content": [
            {"type": "text", "text": "answer"}]}, **BASE),
    ])
    ex = extract_session(p)
    assert "real question" in ex.text and "answer" in ex.text
    assert "sidechain text" not in ex.text
    assert "meta noise" not in ex.text
    assert "huge file dump" not in ex.text


def test_empty_session_returns_none(tmp_path):
    p = write_session(tmp_path, [jl(type="mode", mode="normal")])
    assert extract_session(p) is None


def test_unparseable_lines_skipped(tmp_path):
    p = write_session(tmp_path, [
        "{not json",
        jl(type="user", message={"role": "user", "content": "hello"}, **BASE),
        jl(type="assistant", message={"role": "assistant", "content": [
            {"type": "text", "text": "hi"}]}, **BASE),
    ])
    ex = extract_session(p)
    assert "hello" in ex.text
