#!/usr/bin/env python3
"""
Registry management for llama-spark plugin.
Provides safe JSON mutation operations for the model registry.

Usage:
    registry.py add <name> <path> [--description DESC] [--context-size N] [--gpu-layers N] [--alias ALIAS...]
    registry.py remove <name>
    registry.py list
    registry.py get <name>
"""

import json
import os
import sys
import argparse
import tempfile
from pathlib import Path

CONFIG_FILE = Path.home() / "llama-spark-plugin" / "config" / "models.json"


def load_config():
    """Load the models configuration."""
    if not CONFIG_FILE.exists():
        return {
            "models_dir": str(Path.home() / "models"),
            "models": {},
            "defaults": {
                "host": "127.0.0.1",
                "port": 30000,
                "threads": 8,
                "context_size": 8192,
                "gpu_layers": 99,
                "flash_attn": True
            }
        }
    with open(CONFIG_FILE) as f:
        return json.load(f)


def save_config(config):
    """Save the models configuration atomically."""
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    # Write to temp file first, then atomic rename to prevent corruption
    fd, tmp_path = tempfile.mkstemp(dir=CONFIG_FILE.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(config, f, indent=2)
            f.write("\n")
        os.replace(tmp_path, CONFIG_FILE)
    except Exception:
        os.unlink(tmp_path)
        raise


def add_model(args):
    """Add or update a model in the registry."""
    config = load_config()

    model_entry = {
        "path": args.path,
        "description": args.description or f"Model: {args.name}",
    }

    if args.context_size:
        model_entry["context_size"] = args.context_size
    if args.gpu_layers:
        model_entry["gpu_layers"] = args.gpu_layers
    if args.alias:
        model_entry["aliases"] = args.alias

    # Preserve existing aliases if updating and not overriding
    if args.name in config["models"] and not args.alias:
        existing = config["models"][args.name]
        if "aliases" in existing:
            model_entry["aliases"] = existing["aliases"]

    config["models"][args.name] = model_entry
    save_config(config)

    print(f"Added model '{args.name}' -> {args.path}")


def remove_model(args):
    """Remove a model from the registry."""
    config = load_config()

    if args.name not in config["models"]:
        print(f"Model '{args.name}' not found in registry", file=sys.stderr)
        sys.exit(1)

    del config["models"][args.name]
    save_config(config)

    print(f"Removed model '{args.name}'")


def list_models(args):
    """List all models in the registry."""
    config = load_config()
    models_dir = config.get("models_dir", "")

    if not config["models"]:
        print("No models registered.")
        return

    for name, info in sorted(config["models"].items()):
        path = info["path"]
        if not path.startswith("/"):
            path = f"{models_dir}/{path}"

        # Check if file exists
        exists = Path(path).exists()
        status = "" if exists else " [MISSING]"

        aliases = info.get("aliases", [])
        alias_str = f" (aliases: {', '.join(aliases)})" if aliases else ""

        desc = info.get("description", "")
        print(f"{name}{alias_str}{status}")
        if desc:
            print(f"  {desc}")
        print(f"  {path}")
        print()


def get_model(args):
    """Get details of a specific model as JSON."""
    config = load_config()

    # Direct lookup
    if args.name in config["models"]:
        info = config["models"][args.name]
        info["_name"] = args.name
        print(json.dumps(info, indent=2))
        return

    # Alias lookup
    for name, info in config["models"].items():
        if args.name in info.get("aliases", []):
            info["_name"] = name
            print(json.dumps(info, indent=2))
            return

    print(f"Model '{args.name}' not found", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Manage llama-spark model registry")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Add command
    add_parser = subparsers.add_parser("add", help="Add or update a model")
    add_parser.add_argument("name", help="Model name")
    add_parser.add_argument("path", help="Path to GGUF file (relative to models_dir or absolute)")
    add_parser.add_argument("--description", "-d", help="Model description")
    add_parser.add_argument("--context-size", "-c", type=int, help="Context size")
    add_parser.add_argument("--gpu-layers", "-g", type=int, help="GPU layers to offload")
    add_parser.add_argument("--alias", "-a", action="append", help="Model alias (can repeat)")
    add_parser.set_defaults(func=add_model)

    # Remove command
    remove_parser = subparsers.add_parser("remove", help="Remove a model")
    remove_parser.add_argument("name", help="Model name to remove")
    remove_parser.set_defaults(func=remove_model)

    # List command
    list_parser = subparsers.add_parser("list", help="List all models")
    list_parser.set_defaults(func=list_models)

    # Get command
    get_parser = subparsers.add_parser("get", help="Get model details as JSON")
    get_parser.add_argument("name", help="Model name or alias")
    get_parser.set_defaults(func=get_model)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
