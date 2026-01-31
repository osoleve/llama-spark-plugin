#!/usr/bin/env python3
"""
MCP server for llama.cpp inference.

Reads server state from ~/.llama-server-state.json and exposes
chat completion via the Model Context Protocol.
"""

import json
import httpx
from pathlib import Path
from mcp.server.fastmcp import FastMCP

STATE_FILE = Path.home() / ".llama-server-state.json"
DEFAULT_TIMEOUT = 120.0  # Long timeout for slow generations

# Allowed hosts to prevent SSRF via state file manipulation
ALLOWED_HOSTS = frozenset({"127.0.0.1", "localhost", "0.0.0.0", "::1"})

mcp = FastMCP("llama")


def _read_state() -> dict | None:
    """Read and validate server state. Returns None if server not running."""
    if not STATE_FILE.exists():
        return None

    try:
        state = json.loads(STATE_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return None

    pid = state.get("pid")
    if not pid:
        return None

    # Validate PID is actually llama-server
    try:
        cmdline_path = Path(f"/proc/{pid}/cmdline")
        if not cmdline_path.exists():
            return None
        cmdline = cmdline_path.read_text()
        if "llama-server" not in cmdline:
            return None
    except OSError:
        return None

    return state


def _get_base_url(state: dict) -> tuple[str, str | None]:
    """
    Build base URL from state with host validation.

    Returns (url, error_message). If error_message is not None, url should not be used.
    """
    host = state.get("host", "127.0.0.1")
    port = state.get("port", 30000)

    # SSRF protection: only allow loopback addresses
    if host not in ALLOWED_HOSTS:
        return "", f"Error: Host '{host}' not allowed. Only loopback addresses permitted."

    return f"http://{host}:{port}", None


@mcp.tool()
async def llama_status() -> str:
    """Check if llama-server is running and return its status."""
    state = _read_state()
    if not state:
        return "llama-server is not running. Use /llama:serve to start it."

    base_url, err = _get_base_url(state)
    if err:
        return err

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{base_url}/health")
            if resp.status_code == 200:
                # Safe JSON parsing
                health_data = "ok"
                if resp.headers.get("content-type", "").startswith("application/json"):
                    try:
                        health_data = resp.json()
                    except json.JSONDecodeError:
                        health_data = "ok (parse error)"

                return json.dumps({
                    "status": "running",
                    "model": state.get("model", "unknown"),
                    "port": state.get("port"),
                    "started_at": state.get("started_at"),
                    "health": health_data
                }, indent=2)
    except httpx.RequestError as e:
        return f"llama-server state exists but not responding: {e}"

    return "llama-server health check failed"


@mcp.tool()
async def llama_chat(
    messages: list[dict],
    temperature: float = 0.7,
    max_tokens: int = 2048,
    system_prompt: str | None = None,
) -> str:
    """
    Send a chat completion request to the local llama-server.

    Args:
        messages: List of message dicts with 'role' and 'content' keys.
                  Roles: 'user', 'assistant', 'system'
        temperature: Sampling temperature (0.0-2.0, default 0.7)
        max_tokens: Maximum tokens to generate (default 2048)
        system_prompt: Optional system prompt prepended to messages
                       (ignored if messages already starts with a system message)

    Returns:
        The assistant's response text, or an error message.

    Example:
        llama_chat([{"role": "user", "content": "Explain quicksort"}])
    """
    state = _read_state()
    if not state:
        return "Error: llama-server is not running. Use /llama:serve to start it."

    base_url, err = _get_base_url(state)
    if err:
        return err

    # Prepend system prompt only if provided AND messages doesn't already have one
    if system_prompt and (not messages or messages[0].get("role") != "system"):
        messages = [{"role": "system", "content": system_prompt}] + messages

    payload = {
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stream": False,
    }

    try:
        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            resp = await client.post(
                f"{base_url}/v1/chat/completions",
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            resp.raise_for_status()
            data = resp.json()

            # Extract response text
            choices = data.get("choices", [])
            if not choices:
                return "Error: No response from model"

            message = choices[0].get("message", {})
            content = message.get("content", "")

            return content

    except httpx.TimeoutException:
        return f"Error: Request timed out after {DEFAULT_TIMEOUT}s. Model may be overloaded."
    except httpx.HTTPStatusError as e:
        return f"Error: HTTP {e.response.status_code} - {e.response.text[:500]}"
    except httpx.RequestError as e:
        return f"Error: Could not connect to llama-server at {base_url}: {e}"
    except (json.JSONDecodeError, KeyError) as e:
        return f"Error: Invalid response from llama-server: {e}"


@mcp.tool()
async def llama_complete(
    prompt: str,
    temperature: float = 0.7,
    max_tokens: int = 2048,
    stop: list[str] | None = None,
) -> str:
    """
    Send a raw completion request to the local llama-server.

    Note: Uses llama.cpp's native /completion endpoint, not OpenAI-compatible.

    Args:
        prompt: The text prompt to complete
        temperature: Sampling temperature (0.0-2.0, default 0.7)
        max_tokens: Maximum tokens to generate (default 2048)
        stop: Optional list of stop sequences

    Returns:
        The generated completion text, or an error message.
    """
    state = _read_state()
    if not state:
        return "Error: llama-server is not running. Use /llama:serve to start it."

    base_url, err = _get_base_url(state)
    if err:
        return err

    payload = {
        "prompt": prompt,
        "temperature": temperature,
        "n_predict": max_tokens,
        "stream": False,
    }
    if stop:
        payload["stop"] = stop

    try:
        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            resp = await client.post(
                f"{base_url}/completion",
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            resp.raise_for_status()
            data = resp.json()

            return data.get("content", "")

    except httpx.TimeoutException:
        return f"Error: Request timed out after {DEFAULT_TIMEOUT}s. Model may be overloaded."
    except httpx.HTTPStatusError as e:
        return f"Error: HTTP {e.response.status_code} - {e.response.text[:500]}"
    except httpx.RequestError as e:
        return f"Error: Could not connect to llama-server at {base_url}: {e}"
    except (json.JSONDecodeError, KeyError) as e:
        return f"Error: Invalid response from llama-server: {e}"


if __name__ == "__main__":
    mcp.run()
