#!/usr/bin/env python3
"""
MCP server for vLLM inference on DGX Spark.

Connects to a running vLLM server and exposes chat/completion
via the Model Context Protocol.
"""

import json
import os
import httpx
from mcp.server.fastmcp import FastMCP

# vLLM server configuration
VLLM_URL = os.environ.get("VLLM_URL", "http://localhost:8000")
DEFAULT_TIMEOUT = 120.0  # Long timeout for slow generations

mcp = FastMCP("vllm")

# Cache for model info (refreshed on status check)
_model_cache: dict | None = None


async def _get_models() -> list[dict]:
    """Fetch available models from vLLM server."""
    global _model_cache
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{VLLM_URL}/v1/models")
            if resp.status_code == 200:
                data = resp.json()
                _model_cache = data
                return data.get("data", [])
    except (httpx.RequestError, json.JSONDecodeError):
        pass
    return []


async def _get_default_model() -> str | None:
    """Get the first available model from vLLM."""
    models = await _get_models()
    if models:
        return models[0].get("id")
    return None


@mcp.tool()
async def vllm_status() -> str:
    """Check if vLLM server is running and return its status."""
    try:
        models = await _get_models()
        if not models:
            return f"vLLM server at {VLLM_URL} is not responding or has no models loaded."

        model_list = [m.get("id", "unknown") for m in models]
        return json.dumps({
            "status": "running",
            "url": VLLM_URL,
            "models": model_list,
            "default_model": model_list[0] if model_list else None,
        }, indent=2)

    except httpx.RequestError as e:
        return f"vLLM server at {VLLM_URL} is not responding: {e}"


@mcp.tool()
async def vllm_chat(
    messages: list[dict],
    temperature: float = 0.7,
    max_tokens: int = 2048,
    system_prompt: str | None = None,
    model: str | None = None,
) -> str:
    """
    Send a chat completion request to the vLLM server.

    Args:
        messages: List of message dicts with 'role' and 'content' keys.
                  Roles: 'user', 'assistant', 'system'
        temperature: Sampling temperature (0.0-2.0, default 0.7)
        max_tokens: Maximum tokens to generate (default 2048)
        system_prompt: Optional system prompt prepended to messages
                       (ignored if messages already starts with a system message)
        model: Model to use (default: first available model)

    Returns:
        The assistant's response text, or an error message.

    Example:
        vllm_chat([{"role": "user", "content": "Explain quicksort"}])
    """
    # Get model to use
    if not model:
        model = await _get_default_model()
        if not model:
            return f"Error: vLLM server at {VLLM_URL} has no models available."

    # Prepend system prompt only if provided AND messages doesn't already have one
    if system_prompt and (not messages or messages[0].get("role") != "system"):
        messages = [{"role": "system", "content": system_prompt}] + messages

    payload = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stream": False,
    }

    try:
        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            resp = await client.post(
                f"{VLLM_URL}/v1/chat/completions",
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
        return f"Error: Could not connect to vLLM at {VLLM_URL}: {e}"
    except (json.JSONDecodeError, KeyError) as e:
        return f"Error: Invalid response from vLLM: {e}"


@mcp.tool()
async def vllm_complete(
    prompt: str,
    temperature: float = 0.7,
    max_tokens: int = 2048,
    stop: list[str] | None = None,
    model: str | None = None,
) -> str:
    """
    Send a raw completion request to the vLLM server.

    Args:
        prompt: The text prompt to complete
        temperature: Sampling temperature (0.0-2.0, default 0.7)
        max_tokens: Maximum tokens to generate (default 2048)
        stop: Optional list of stop sequences
        model: Model to use (default: first available model)

    Returns:
        The generated completion text, or an error message.
    """
    # Get model to use
    if not model:
        model = await _get_default_model()
        if not model:
            return f"Error: vLLM server at {VLLM_URL} has no models available."

    payload = {
        "model": model,
        "prompt": prompt,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stream": False,
    }
    if stop:
        payload["stop"] = stop

    try:
        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            resp = await client.post(
                f"{VLLM_URL}/v1/completions",
                json=payload,
                headers={"Content-Type": "application/json"},
            )
            resp.raise_for_status()
            data = resp.json()

            # Extract completion text
            choices = data.get("choices", [])
            if not choices:
                return "Error: No response from model"

            return choices[0].get("text", "")

    except httpx.TimeoutException:
        return f"Error: Request timed out after {DEFAULT_TIMEOUT}s. Model may be overloaded."
    except httpx.HTTPStatusError as e:
        return f"Error: HTTP {e.response.status_code} - {e.response.text[:500]}"
    except httpx.RequestError as e:
        return f"Error: Could not connect to vLLM at {VLLM_URL}: {e}"
    except (json.JSONDecodeError, KeyError) as e:
        return f"Error: Invalid response from vLLM: {e}"


if __name__ == "__main__":
    mcp.run()
