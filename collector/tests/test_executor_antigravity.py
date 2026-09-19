import pytest
from collector.executor import build_agent_command, discover_antigravity_env


def test_build_agent_command_antigravity_basic():
    cmd = build_agent_command(
        binary="antigravity",
        resolved="/opt/homebrew/bin/agy",
        prompt="hello world",
    )
    assert cmd == ["/opt/homebrew/bin/agy", "-p", "hello world"]


def test_build_agent_command_antigravity_resume_and_model():
    cmd = build_agent_command(
        binary="agy",
        resolved="/opt/homebrew/bin/agy",
        prompt="continue work",
        session_id="af1da38e-a90d-44f9-83a8-f9c5f10846e6",
        model="pro",
    )
    assert cmd == [
        "/opt/homebrew/bin/agy",
        "--resume", "af1da38e-a90d-44f9-83a8-f9c5f10846e6",
        "--model", "pro",
        "-p", "continue work",
    ]


def test_discover_antigravity_env_when_running():
    # If Antigravity is running on this machine, discover should succeed and return valid dict
    env = discover_antigravity_env()
    if env is not None:
        assert "ANTIGRAVITY_LS_ADDRESS" in env
        assert env["ANTIGRAVITY_LS_ADDRESS"].startswith("localhost:")
