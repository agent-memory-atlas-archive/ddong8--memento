import os
from collector.executor import build_agent_command, resolve_batch_script


def test_build_agent_command_non_windows():
    cmd = build_agent_command(
        binary="codex",
        resolved="/usr/local/bin/codex",
        prompt="hello world",
        is_windows=False,
    )
    assert cmd[:2] == ["/usr/local/bin/codex", "exec"]
    assert "hello world" in cmd


def test_build_agent_command_windows_exe_with_spaces():
    cmd = build_agent_command(
        binary="codex",
        resolved=r"C:\Program Files\OpenAI\codex.exe",
        prompt="hello world",
        is_windows=True,
    )
    assert cmd[0] == r"C:\Program Files\OpenAI\codex.exe"
    assert cmd[1] == "exec"
    assert "hello world" in cmd


def test_build_agent_command_windows_npm_batch_script(tmp_path):
    # Simulate C:\Program Files\nodejs\codex.cmd
    node_dir = tmp_path / "Program Files" / "nodejs"
    node_dir.mkdir(parents=True)
    cmd_file = node_dir / "codex.cmd"
    node_exe = node_dir / "node.exe"
    node_exe.write_text("dummy node binary")

    js_dir = node_dir / "node_modules" / "@openai" / "codex" / "bin"
    js_dir.mkdir(parents=True)
    js_file = js_dir / "codex.js"
    js_file.write_text("// dummy js script")

    npm_content = f"""@ECHO off
GOTO start
:find_dp0
SET dp0=%~dp0
EXIT /b
:start
SETLOCAL
CALL :find_dp0

IF EXIST "%dp0%\\node.exe" (
  SET "_prog=%dp0%\\node.exe"
) ELSE (
  SET "_prog=node"
  SET PATHEXT=%PATHEXT:;.JS;=;%
)

endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & "%_prog%"  "%dp0%\\node_modules\\@openai\\codex\\bin\\codex.js" %*
"""
    cmd_file.write_text(npm_content, encoding="utf-8")

    cmd = build_agent_command(
        binary="codex",
        resolved=str(cmd_file),
        prompt="test prompt",
        is_windows=True,
    )

    # Should resolve directly to node.exe and codex.js, bypassing cmd.exe!
    assert cmd[0] == str(node_exe)
    assert cmd[1] == str(js_file)
    assert cmd[2] == "exec"
    assert "test prompt" in cmd


def test_build_agent_command_windows_python_batch_script(tmp_path):
    bin_dir = tmp_path / "AppData" / "Local" / "agy" / "bin"
    bin_dir.mkdir(parents=True)
    cmd_file = bin_dir / "agy.cmd"
    py_script = bin_dir / "agy_cli.py"
    py_script.write_text("# dummy py script")

    cmd_file.write_text(f'@echo off\r\npython "{str(py_script)}" %*\r\n', encoding="utf-8")

    cmd = build_agent_command(
        binary="agy",
        resolved=str(cmd_file),
        prompt="fix bug",
        is_windows=True,
    )

    # Should resolve directly to python and agy_cli.py
    assert cmd[0] in ("python", "python3") or cmd[0].endswith("python") or cmd[0].endswith("python3")
    assert cmd[1] == str(py_script)
    assert "-p" in cmd
    assert "fix bug" in cmd


def test_build_agent_command_windows_arbitrary_batch_script(tmp_path):
    cmd_file = tmp_path / "custom_tool.bat"
    cmd_file.write_text("@echo custom batch", encoding="utf-8")

    cmd = build_agent_command(
        binary="claude",
        resolved=str(cmd_file),
        prompt="review",
        is_windows=True,
    )

    # Should be wrapped with cmd.exe /d /c call to prevent C:\Program whitespace splits
    assert cmd[1] == "/d"
    assert cmd[2] == "/c"
    assert cmd[3] == "call"
    assert cmd[4] == str(cmd_file)
    assert "-p" in cmd
    assert "review" in cmd
