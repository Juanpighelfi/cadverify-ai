"""Where the project lives, its .env, and the Meta Model API client of a run."""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

from cadverify.meta_api import MetaClient

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def load_env() -> None:
    load_dotenv(PROJECT_ROOT / ".env", override=False)


def api_key_present() -> bool:
    load_env()
    return bool(os.environ.get("MODEL_API_KEY", "").strip())


def make_client(run_dir: Path) -> MetaClient:
    """A client that records every request of the run in <run_dir>/raw/, without the key."""
    load_env()
    return MetaClient(raw_dir=run_dir / "raw")
