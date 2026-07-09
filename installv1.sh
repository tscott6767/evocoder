#!/usr/bin/env bash
# ============================================================================
# EvoCoder — Autonomous Evolutionary Coding Engine
# Complete install.sh — Full rewrite (2025-07-09)
#
# Recreates all 14 EvoCoder source files, sets up a Python venv,
# installs dependencies, and optionally builds the Docker sandbox.
#
# Usage:
#   chmod +x install.sh
#   ./install.sh [target_dir]    # default: ./evocoder
#
# All code is embedded in heredocs with unique EOF markers.
# No triple-backtick fences inside heredocs.
# ============================================================================

set -euo pipefail

TARGET_DIR="${1:-./evocoder}"
SCRIPT_VERSION="2.0.0"
SANDBOX_IMAGE="evocoder-sandbox:latest"

# ─── Color output ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

echo ""
echo "=============================================="
echo "  EvoCoder v${SCRIPT_VERSION} — Installer"
echo "  Autonomous Evolutionary Coding Engine"
echo "=============================================="
echo ""

# ─── Pre-flight checks ───
info "Checking prerequisites..."

if ! command -v python3 &>/dev/null; then
    err "python3 is required but not found."
    exit 1
fi
ok "python3 found: $(python3 --version)"

if ! command -v pip3 &>/dev/null; then
    warn "pip3 not found. Attempting to install..."
    python3 -m ensurepip --upgrade 2>/dev/null || {
        err "pip is required. Install with: python3 -m ensurepip --upgrade"
        exit 1
    }
fi
ok "pip3 available"

HAS_DOCKER=false
if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
        HAS_DOCKER=true
        ok "Docker found and running"
    else
        warn "Docker found but not running. Sandbox disabled."
    fi
else
    warn "Docker not found. Sandbox code execution disabled."
    warn "System still works — judging falls back to static + LLM."
fi

# ─── Create directory structure ───
info "Creating directory structure at ${TARGET_DIR}..."
mkdir -p "${TARGET_DIR}"
cd "${TARGET_DIR}"
mkdir -p core domains judges models prompts sandbox static
ok "Directory structure created"

# ============================================================================
# FILE 1: __init__.py files (7 package markers)
# ============================================================================
info "Writing __init__.py files..."

cat > __init__.py << 'EOF___EVOCODER_ROOT_INIT'
# EvoCoder — Autonomous Evolutionary Coding Engine
# Root package
EOF

cat > core/__init__.py << 'EOF___EVOCODER_CORE_INIT'
# EvoCoder core package — schemas, persistence, controller, meta_agent
EOF

cat > domains/__init__.py << 'EOF___EVOCODER_DOMAINS_INIT'
# Domain plugins — pluggable language-specific configurations
EOF

cat > judges/__init__.py << 'EOF___EVOCODER_JUDGES_INIT'
# Judge system — static, LLM, and hybrid evaluation
EOF

cat > models/__init__.py << 'EOF___EVOCODER_MODELS_INIT'
# Model adapters — async OpenAI-compatible API client
EOF

cat > prompts/__init__.py << 'EOF___EVOCODER_PROMPTS_INIT'
# Prompt templates — Jinja2-based dynamic prompt generation
EOF

cat > sandbox/__init__.py << 'EOF___EVOCODER_SANDBOX_INIT'
# Sandbox system — Docker-based isolated code execution
EOF

ok "7 __init__.py files written"

# ============================================================================
# FILE 2: core/schemas.py — Data models
# ============================================================================
info "Writing core/schemas.py..."

cat > core/schemas.py << 'EOF___EVOCODER_SCHEMAS'
from __future__ import annotations

import enum
import uuid
import time
from dataclasses import dataclass, field
from typing import Optional, Any


class Side(enum.Enum):
    A = "A"
    B = "B"


class JudgeMode(enum.Enum):
    STATIC = "static"
    LLM = "llm"
    HYBRID = "hybrid"


@dataclass
class DomainConfig:
    """Configuration for a coding domain (language-specific rules)."""
    name: str = "generic"
    language: str = "text"
    banned_patterns: list[str] = field(default_factory=list)
    reward_patterns: list[str] = field(default_factory=list)
    rubric: str = ""
    file_extension: str = ".txt"
    extra_context: str = ""
    compile_cmd: Optional[str] = None
    test_cmd: Optional[str] = None


@dataclass
class Task:
    """A coding task that models compete to solve."""
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:16])
    description: str = ""
    domain: str = "generic"
    max_rounds: int = 5
    judge_mode: str = "hybrid"
    rules_override: Optional[dict] = None
    created_at: float = field(default_factory=time.time)


@dataclass
class Submission:
    """A code submission from one side in a round."""
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:16])
    task_id: str = ""
    round: int = 0
    side: Side = Side.A
    model: str = ""
    code: str = ""
    prompt: str = ""
    parent_id: Optional[str] = None
    generation: int = 0
    created_at: float = field(default_factory=time.time)


@dataclass
class Verdict:
    """A judge's evaluation of a submission."""
    submission_id: str = ""
    task_id: str = ""
    round: int = 0
    score: float = 0.0
    passed: bool = False
    reasoning: str = ""
    banned_hits: list[str] = field(default_factory=list)
    missing_patterns: list[str] = field(default_factory=list)
    reward_hits: list[str] = field(default_factory=list)
    compile_success: Optional[bool] = None
    compile_output: str = ""
    test_success: Optional[bool] = None
    test_output: str = ""
    created_at: float = field(default_factory=time.time)


@dataclass
class Lineage:
    """Evolutionary lineage record — tracks parent-child relationships."""
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:16])
    submission_id: str = ""
    parent_id: Optional[str] = None
    generation: int = 0
    score: float = 0.0
    side: Side = Side.A
    is_winner: bool = False
    is_promoted: bool = False
    created_at: float = field(default_factory=time.time)


@dataclass
class MetaChange:
    """A meta-agent proposed change to the judge/domain configuration."""
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:16])
    task_id: str = ""
    round: int = 0
    target_file: str = "domain_config"
    patch: str = ""          # JSON string of changes
    reasoning: str = ""
    fitness_before: float = 0.0
    fitness_after: Optional[float] = None
    applied: int = 0         # 0 = not yet, 1 = applied
    promoted: int = 0       # 0 = reverted, 1 = promoted
    created_at: float = field(default_factory=time.time)


# ─── Pydantic models for API validation ───
try:
    from pydantic import BaseModel, Field as PydField

    class BattleConfig(BaseModel):
        task_description: str = PydField(..., description="The task to evolve code for")
        domain: str = PydField("generic", description="Domain plugin name")
        side_a_model: str = PydField("qwen2-coder:14b")
        side_b_model: str = PydField("mistral:8x7b-instruct")
        judge_model: str = PydField("qwen3-coder:30b")
        meta_model: str = PydField("", description="Meta-agent model. Empty = disabled")
        rounds: int = PydField(5, ge=1, le=50)
        judge_mode: JudgeMode = PydField(default=JudgeMode.HYBRID)
        enable_meta: bool = PydField(False, description="Enable self-referential improvement")
        meta_interval: int = PydField(3, description="Run meta-agent every N rounds")
        rules_override: Optional[dict] = None
        api_base: str = PydField("http://localhost:11434/v1")
        api_key: str = PydField("")

except ImportError:
    # Fallback: use dataclass if pydantic not available
    @dataclass
    class BattleConfig:
        task_description: str = ""
        domain: str = "generic"
        side_a_model: str = "qwen2-coder:14b"
        side_b_model: str = "mistral:8x7b-instruct"
        judge_model: str = "qwen3-coder:30b"
        meta_model: str = ""
        rounds: int = 5
        judge_mode: JudgeMode = JudgeMode.HYBRID
        enable_meta: bool = False
        meta_interval: int = 3
        rules_override: Optional[dict] = None
        api_base: str = "http://localhost:11434/v1"
        api_key: str = ""
EOF

ok "core/schemas.py written"

# ============================================================================
# FILE 3: core/persistence.py — SQLite layer
# ============================================================================
info "Writing core/persistence.py..."

cat > core/persistence.py << 'EOF___EVOCODER_PERSISTENCE'
from __future__ import annotations

import sqlite3
import json
import logging
import time
from pathlib import Path
from typing import Optional
from core.schemas import (
    Task, Submission, Verdict, Lineage, MetaChange, Side
)

logger = logging.getLogger("evocoder.persistence")

DEFAULT_DB_PATH = Path("evocoder.db")
ELO_K_FACTOR = 32
ELO_DEFAULT = 1200


def init_db(db_path: Path = DEFAULT_DB_PATH) -> None:
    """Initialize the SQLite database with all required tables."""
    conn = get_db(db_path)
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        domain TEXT NOT NULL,
        max_rounds INTEGER DEFAULT 5,
        judge_mode TEXT DEFAULT 'hybrid',
        rules_override TEXT,
        created_at REAL
    );

    CREATE TABLE IF NOT EXISTS submissions (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        round INTEGER NOT NULL,
        side TEXT NOT NULL,
        model TEXT NOT NULL,
        code TEXT NOT NULL DEFAULT '',
        prompt TEXT DEFAULT '',
        parent_id TEXT,
        generation INTEGER DEFAULT 0,
        created_at REAL,
        FOREIGN KEY (task_id) REFERENCES tasks(id)
    );

    CREATE TABLE IF NOT EXISTS verdicts (
        id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
        submission_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        round INTEGER NOT NULL,
        score REAL DEFAULT 0.0,
        passed INTEGER DEFAULT 0,
        reasoning TEXT DEFAULT '',
        banned_hits TEXT DEFAULT '[]',
        missing_patterns TEXT DEFAULT '[]',
        reward_hits TEXT DEFAULT '[]',
        compile_success TEXT,
        compile_output TEXT DEFAULT '',
        test_success TEXT,
        test_output TEXT DEFAULT '',
        created_at REAL,
        FOREIGN KEY (submission_id) REFERENCES submissions(id),
        FOREIGN KEY (task_id) REFERENCES tasks(id)
    );

    CREATE TABLE IF NOT EXISTS lineage (
        id TEXT PRIMARY KEY,
        submission_id TEXT NOT NULL,
        parent_id TEXT,
        generation INTEGER NOT NULL,
        score REAL DEFAULT 0.0,
        side TEXT NOT NULL,
        is_winner INTEGER DEFAULT 0,
        is_promoted INTEGER DEFAULT 0,
        created_at REAL,
        FOREIGN KEY (submission_id) REFERENCES submissions(id)
    );

    CREATE TABLE IF NOT EXISTS leaderboard (
        model TEXT PRIMARY KEY,
        elo_rating REAL DEFAULT 1200.0,
        wins INTEGER DEFAULT 0,
        losses INTEGER DEFAULT 0,
        total_score REAL DEFAULT 0.0,
        battles INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS meta_changes (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        round INTEGER NOT NULL,
        target_file TEXT DEFAULT 'domain_config',
        patch TEXT DEFAULT '',
        reasoning TEXT DEFAULT '',
        fitness_before REAL DEFAULT 0.0,
        fitness_after REAL,
        applied INTEGER DEFAULT 0,
        promoted INTEGER DEFAULT 0,
        created_at REAL,
        FOREIGN KEY (task_id) REFERENCES tasks(id)
    );

    CREATE INDEX IF NOT EXISTS idx_submissions_task ON submissions(task_id);
    CREATE INDEX IF NOT EXISTS idx_submissions_round ON submissions(task_id, round);
    CREATE INDEX IF NOT EXISTS idx_verdicts_sub ON verdicts(submission_id);
    CREATE INDEX IF NOT EXISTS idx_verdicts_round ON verdicts(task_id, round);
    CREATE INDEX IF NOT EXISTS idx_lineage_sub ON lineage(submission_id);
    CREATE INDEX IF NOT EXISTS idx_meta_task ON meta_changes(task_id);
    """)
    conn.commit()
    conn.close()


def get_db(db_path: Path = DEFAULT_DB_PATH) -> sqlite3.Connection:
    """Get a SQLite connection with Row factory."""
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def save_task(conn: sqlite3.Connection, task: Task) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO tasks (id, description, domain, max_rounds, "
        "judge_mode, rules_override, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (task.id, task.description, task.domain, task.max_rounds,
         task.judge_mode, json.dumps(task.rules_override) if task.rules_override else None,
         task.created_at)
    )
    conn.commit()


def save_submission(conn: sqlite3.Connection, sub: Submission) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO submissions (id, task_id, round, side, model, "
        "code, prompt, parent_id, generation, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (sub.id, sub.task_id, sub.round, sub.side.value, sub.model,
         sub.code, sub.prompt, sub.parent_id, sub.generation, sub.created_at)
    )
    conn.commit()


def save_verdict(conn: sqlite3.Connection, v: Verdict) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO verdicts (submission_id, task_id, round, score, "
        "passed, reasoning, banned_hits, missing_patterns, reward_hits, "
        "compile_success, compile_output, test_success, test_output, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (v.submission_id, v.task_id, v.round, v.score, int(v.passed),
         v.reasoning, json.dumps(v.banned_hits), json.dumps(v.missing_patterns),
         json.dumps(v.reward_hits),
         str(v.compile_success) if v.compile_success is not None else None,
         v.compile_output,
         str(v.test_success) if v.test_success is not None else None,
         v.test_output, v.created_at)
    )
    conn.commit()


def save_lineage(conn: sqlite3.Connection, lin: Lineage) -> None:
    conn.execute(
        "INSERT INTO lineage (id, submission_id, parent_id, generation, score, "
        "side, is_winner, is_promoted, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (lin.id, lin.submission_id, lin.parent_id, lin.generation, lin.score,
         lin.side.value, int(lin.is_winner), int(lin.is_promoted), lin.created_at)
    )
    conn.commit()


def save_meta_change(conn: sqlite3.Connection, mc: MetaChange) -> None:
    conn.execute(
        "INSERT INTO meta_changes (id, task_id, round, target_file, patch, "
        "reasoning, fitness_before, fitness_after, applied, promoted, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (mc.id, mc.task_id, mc.round, mc.target_file, mc.patch,
         mc.reasoning, mc.fitness_before, mc.fitness_after,
         mc.applied, mc.promoted, mc.created_at)
    )
    conn.commit()


def update_meta_change(conn: sqlite3.Connection, mc_id: str,
                       applied: int = None, promoted: int = None,
                       fitness_after: float = None) -> None:
    """Update a meta-change record with promotion/revert results."""
    updates = []
    params = []
    if applied is not None:
        updates.append("applied = ?")
        params.append(applied)
    if promoted is not None:
        updates.append("promoted = ?")
        params.append(promoted)
    if fitness_after is not None:
        updates.append("fitness_after = ?")
        params.append(fitness_after)
    if not updates:
        return
    params.append(mc_id)
    conn.execute(
        f"UPDATE meta_changes SET {', '.join(updates)} WHERE id = ?",
        params
    )
    conn.commit()


def _row_to_submission(row: sqlite3.Row) -> Submission:
    return Submission(
        id=row["id"], task_id=row["task_id"], round=row["round"],
        side=Side(row["side"]), model=row["model"], code=row["code"],
        prompt=row["prompt"] or "", parent_id=row["parent_id"],
        generation=row["generation"], created_at=row["created_at"]
    )


def _row_to_verdict(row: sqlite3.Row) -> Verdict:
    return Verdict(
        submission_id=row["submission_id"], task_id=row["task_id"],
        round=row["round"], score=row["score"],
        passed=bool(row["passed"]), reasoning=row["reasoning"] or "",
        banned_hits=json.loads(row["banned_hits"] or "[]"),
        missing_patterns=json.loads(row["missing_patterns"] or "[]"),
        reward_hits=json.loads(row["reward_hits"] or "[]"),
        compile_success=_parse_bool(row["compile_success"]),
        compile_output=row["compile_output"] or "",
        test_success=_parse_bool(row["test_success"]),
        test_output=row["test_output"] or "",
        created_at=row["created_at"]
    )


def _parse_bool(val) -> Optional[bool]:
    if val is None:
        return None
    s = str(val).strip().lower()
    if s == "true":
        return True
    if s == "false":
        return False
    return None


def get_winning_submission(conn: sqlite3.Connection,
                           task_id: str, round_num: int) -> Optional[Submission]:
    """Get the winning submission for a given round."""
    row = conn.execute(
        "SELECT s.* FROM submissions s "
        "JOIN lineage l ON s.id = l.submission_id "
        "WHERE s.task_id = ? AND s.round = ? AND l.is_winner = 1 "
        "ORDER BY l.created_at DESC LIMIT 1",
        (task_id, round_num)
    ).fetchone()
    return _row_to_submission(row) if row else None


def get_last_round(conn: sqlite3.Connection, task_id: str) -> int:
    """Get the last completed round number for a task."""
    row = conn.execute(
        "SELECT MAX(round) as max_round FROM submissions WHERE task_id = ?",
        (task_id,)
    ).fetchone()
    return row["max_round"] if row and row["max_round"] else 0


def get_submissions_for_round(conn: sqlite3.Connection,
                               task_id: str, round_num: int) -> list[Submission]:
    rows = conn.execute(
        "SELECT * FROM submissions WHERE task_id = ? AND round = ?",
        (task_id, round_num)
    ).fetchall()
    return [_row_to_submission(r) for r in rows]


def get_verdicts_for_round(conn: sqlite3.Connection,
                           task_id: str, round_num: int) -> list[Verdict]:
    rows = conn.execute(
        "SELECT * FROM verdicts WHERE task_id = ? AND round = ?",
        (task_id, round_num)
    ).fetchall()
    return [_row_to_verdict(r) for r in rows]


def update_leaderboard(conn: sqlite3.Connection, model: str,
                       won: bool, score: float) -> None:
    """Update ELO rating for a model after a battle round."""
    row = conn.execute(
        "SELECT * FROM leaderboard WHERE model = ?", (model,)
    ).fetchone()

    if row:
        old_elo = row["elo_rating"]
        # Simplified ELO: opponent is average of all others
        # For a 2-player game, expected score = 1 / (1 + 10^((opp - self) / 400))
        # Since we don't track opponent here, use a simple update
        expected = 0.5  # assume 50/50 baseline
        actual = 1.0 if won else 0.0
        new_elo = old_elo + ELO_K_FACTOR * (actual - expected)

        conn.execute(
            "UPDATE leaderboard SET elo_rating = ?, wins = wins + ?, "
            "losses = losses + ?, total_score = total_score + ?, "
            "battles = battles + 1 WHERE model = ?",
            (new_elo, int(won), int(not won), score, model)
        )
    else:
        elo = ELO_DEFAULT + (ELO_K_FACTOR * (1.0 if won else -0.5))
        conn.execute(
            "INSERT INTO leaderboard (model, elo_rating, wins, losses, "
            "total_score, battles) VALUES (?, ?, ?, ?, ?, 1)",
            (model, elo, int(won), int(not won), score)
        )
    conn.commit()


def get_leaderboard(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        "SELECT * FROM leaderboard ORDER BY elo_rating DESC"
    ).fetchall()
    return [dict(r) for r in rows]


def get_continuation_context(conn: sqlite3.Connection) -> dict:
    """Get context for continuing a previous battle."""
    row = conn.execute(
        "SELECT * FROM tasks ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    if not row:
        return {"has_previous": False}
    task_id = row["id"]
    last_round = get_last_round(conn, task_id)
    winner = get_winning_submission(conn, task_id, last_round) if last_round > 0 else None
    return {
        "has_previous": True,
        "task_id": task_id,
        "description": row["description"],
        "domain": row["domain"],
        "last_round": last_round,
        "last_winner_model": winner.model if winner else None,
    }


def get_meta_changes(conn: sqlite3.Connection, task_id: str) -> list[dict]:
    rows = conn.execute(
        "SELECT * FROM meta_changes WHERE task_id = ? ORDER BY round ASC",
        (task_id,)
    ).fetchall()
    return [dict(r) for r in rows]


def get_lineage_tree(conn: sqlite3.Connection, task_id: str) -> list[dict]:
    rows = conn.execute(
        "SELECT l.*, s.model, s.code FROM lineage l "
        "JOIN submissions s ON l.submission_id = s.id "
        "WHERE s.task_id = ? ORDER BY l.generation ASC, l.is_winner DESC",
        (task_id,)
    ).fetchall()
    return [dict(r) for r in rows]
EOF

ok "core/persistence.py written"

# ============================================================================
# FILE 4: models/model_adapters.py — Async OpenAI-compatible adapter
# ============================================================================
info "Writing models/model_adapters.py..."

cat > models/model_adapters.py << 'EOF___EVOCODER_MODEL_ADAPTERS'
from __future__ import annotations

import asyncio
import logging
from typing import Optional

try:
    import httpx
    HAS_HTTPX = True
except ImportError:
    HAS_HTTPX = False

logger = logging.getLogger("evocoder.models")


class ModelAdapter:
    """
    Async adapter for any OpenAI-compatible API.
    Works with Ollama, vLLM, llama.cpp, OpenAI, OpenRouter, etc.
    """

    def __init__(self, model: str, api_base: str = "http://localhost:11434/v1",
                 api_key: str = "", timeout: float = 120.0):
        self.model = model
        self.api_base = api_base.rstrip("/")
        self.api_key = api_key or "ollama"  # Ollama accepts any key
        self.timeout = timeout
        self._client = None

    def _get_client(self):
        if self._client is None:
            if HAS_HTTPX:
                self._client = httpx.AsyncClient(
                    base_url=self.api_base,
                    timeout=httpx.Timeout(self.timeout, connect=10.0),
                    headers={"Authorization": f"Bearer {self.api_key}"}
                )
            else:
                raise RuntimeError("httpx not installed. Run: pip install httpx")
        return self._client

    async def complete(self, system: str, user: str,
                       temperature: float = 0.7,
                       max_tokens: int = 4096) -> str:
        """
        Send a chat completion request and return the assistant's message text.
        """
        client = self._get_client()

        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature,
            "max_tokens": max_tokens,
        }

        try:
            response = await client.post("/chat/completions", json=payload)
            response.raise_for_status()
            data = response.json()
            return data["choices"][0]["message"]["content"]
        except Exception as e:
            logger.error("Model %s request failed: %s", self.model, e)
            raise

    async def close(self):
        if self._client is not None:
            await self._client.aclose()
            self._client = None


def make_adapter(model: str, api_base: str = "http://localhost:11434/v1",
                 api_key: str = "") -> ModelAdapter:
    """Factory function to create a model adapter."""
    return ModelAdapter(model, api_base, api_key)
EOF

ok "models/model_adapters.py written"

# ============================================================================
# FILE 5: judges/judge.py — Static, LLM, and Hybrid judges
# ============================================================================
info "Writing judges/judge.py..."

cat > judges/judge.py << 'EOF___EVOCODER_JUDGE'
from __future__ import annotations

import json
import logging
import re
from typing import Optional

from core.schemas import Submission, Verdict, DomainConfig, JudgeMode, Side
from models.model_adapters import ModelAdapter
from sandbox.sandbox import DockerSandbox, NullSandbox

logger = logging.getLogger("evocoder.judge")


class BaseJudge:
    """Base class for all judges."""

    async def evaluate(self, submission: Submission,
                       domain: DomainConfig) -> Verdict:
        raise NotImplementedError


class StaticJudge(BaseJudge):
    """
    Fast, free static analysis using regex patterns.
    Checks banned patterns (instant fail) and reward patterns (score boost).
    """

    async def evaluate(self, submission: Submission,
                       domain: DomainConfig) -> Verdict:
        banned_hits = []
        reward_hits = []
        missing_patterns = []

        code = submission.code

        for pattern in domain.banned_patterns:
            try:
                if re.search(pattern, code):
                    banned_hits.append(pattern)
            except re.error:
                if pattern in code:
                    banned_hits.append(pattern)

        for pattern in domain.reward_patterns:
            try:
                if re.search(pattern, code):
                    reward_hits.append(pattern)
                else:
                    missing_patterns.append(pattern)
            except re.error:
                if pattern in code:
                    reward_hits.append(pattern)
                else:
                    missing_patterns.append(pattern)

        # Calculate score
        if banned_hits:
            score = 0.0
            passed = False
            reasoning = f"Failed: banned patterns detected: {', '.join(banned_hits)}"
        else:
            total_reward = len(domain.reward_patterns)
            matched = len(reward_hits)
            if total_reward > 0:
                score = (matched / total_reward) * 10.0
            else:
                score = 5.0  # neutral if no patterns defined
            passed = score >= 6.0
            reasoning = f"Matched {matched}/{total_reward} reward patterns."

        return Verdict(
            submission_id=submission.id,
            task_id=submission.task_id,
            round=submission.round,
            score=round(score, 2),
            passed=passed,
            reasoning=reasoning,
            banned_hits=banned_hits,
            missing_patterns=missing_patterns,
            reward_hits=reward_hits,
        )


class LLMJudge(BaseJudge):
    """
    Uses an LLM to evaluate code quality against a domain rubric.
    More nuanced than static analysis — handles any language.
    """

    def __init__(self, judge_adapter: ModelAdapter):
        self.adapter = judge_adapter

    async def evaluate(self, submission: Submission,
                       domain: DomainConfig) -> Verdict:
        from prompts.templates import render_judge_prompt

        system, user = render_judge_prompt(domain, submission.code)

        try:
            response = await self.adapter.complete(system, user, temperature=0.1)

            # Strip markdown code fences if present
            response = response.strip()
            if response.startswith("```"):
                lines = response.split("\n")
                response = "\n".join(lines[1:-1]) if lines[-1].startswith("```") else "\n".join(lines[1:])

            result = json.loads(response)

            # Run static checks too (for banned_hits/reward_hits population)
            banned_hits = []
            reward_hits = []
            missing_patterns = []
            for pattern in domain.banned_patterns:
                try:
                    if re.search(pattern, submission.code):
                        banned_hits.append(pattern)
                except re.error:
                    if pattern in submission.code:
                        banned_hits.append(pattern)
            for pattern in domain.reward_patterns:
                try:
                    if re.search(pattern, submission.code):
                        reward_hits.append(pattern)
                    else:
                        missing_patterns.append(pattern)
                except re.error:
                    if pattern in submission.code:
                        reward_hits.append(pattern)
                    else:
                        missing_patterns.append(pattern)

            score = float(result.get("score", 0.0))
            score = max(0.0, min(10.0, score))

            if banned_hits:
                score = 0.0

            return Verdict(
                submission_id=submission.id,
                task_id=submission.task_id,
                round=submission.round,
                score=score,
                passed=result.get("passed", score >= 6.0) and not banned_hits,
                reasoning=result.get("reasoning", ""),
                banned_hits=banned_hits,
                missing_patterns=missing_patterns,
                reward_hits=reward_hits,
            )

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            logger.error("LLM judge parse error: %s", e)
            return Verdict(
                submission_id=submission.id,
                task_id=submission.task_id,
                round=submission.round,
                score=0.0,
                passed=False,
                reasoning=f"LLM judge failed to parse response: {e}",
            )


class HybridJudge(BaseJudge):
    """
    Combines static analysis + LLM rubric + optional Docker execution.
    This is the most thorough judge mode.
    """

    def __init__(self, judge_adapter: ModelAdapter, sandbox=None,
                 enable_execution: bool = True):
        self.llm_judge = LLMJudge(judge_adapter)
        self.static_judge = StaticJudge()
        self.sandbox = sandbox
        self.enable_execution = enable_execution

    async def evaluate(self, submission: Submission,
                       domain: DomainConfig) -> Verdict:
        # Step 1: Static check (fast-fail on banned patterns)
        static_verdict = await self.static_judge.evaluate(submission, domain)

        if static_verdict.banned_hits and not static_verdict.reward_hits:
            logger.info("Static judge: instant fail (banned patterns)")
            return static_verdict

        # Step 2: LLM rubric evaluation
        llm_verdict = await self.llm_judge.evaluate(submission, domain)

        # Merge: take LLM score but keep static pattern data
        merged = Verdict(
            submission_id=submission.id,
            task_id=submission.task_id,
            round=submission.round,
            score=llm_verdict.score,
            passed=llm_verdict.passed and not static_verdict.banned_hits,
            reasoning=llm_verdict.reasoning,
            banned_hits=static_verdict.banned_hits,
            missing_patterns=static_verdict.missing_patterns,
            reward_hits=static_verdict.reward_hits,
        )

        # Step 3: Docker execution (if available and enabled)
        if self.enable_execution and self.sandbox and self.sandbox.available:
            if domain.compile_cmd or domain.test_cmd:
                logger.info("Running sandbox execution for submission %s", submission.id[:8])
                result = await self.sandbox.run_code(
                    code=submission.code,
                    file_extension=domain.file_extension,
                    compile_cmd=domain.compile_cmd,
                    test_cmd=domain.test_cmd,
                )
                merged.compile_success = result["compile_success"]
                merged.compile_output = result["compile_output"]
                merged.test_success = result["test_success"]
                merged.test_output = result["test_output"]

                # Penalize compilation failures
                if merged.compile_success is False:
                    merged.score = max(0.0, merged.score - 3.0)
                    merged.reasoning += f" [Compilation failed: {merged.compile_output[:200]}]"
                if merged.test_success is False:
                    merged.score = max(0.0, merged.score - 2.0)
                    merged.reasoning += f" [Tests failed: {merged.test_output[:200]}]"
                merged.passed = merged.passed and merged.compile_success is not False

        return merged


def make_judge(mode: JudgeMode, judge_adapter: ModelAdapter = None,
               sandbox=None, enable_execution: bool = True) -> BaseJudge:
    """Factory function to create a judge based on mode."""
    if mode == JudgeMode.STATIC:
        return StaticJudge()
    elif mode == JudgeMode.LLM:
        if judge_adapter is None:
            raise ValueError("LLM judge requires a judge_adapter")
        return LLMJudge(judge_adapter)
    elif mode == JudgeMode.HYBRID:
        if judge_adapter is None:
            raise ValueError("Hybrid judge requires a judge_adapter")
        return HybridJudge(judge_adapter, sandbox, enable_execution)
    else:
        raise ValueError(f"Unknown judge mode: {mode}")
EOF

ok "judges/judge.py written"

# ============================================================================
# FILE 6: core/controller.py — Battle orchestration engine
# ============================================================================
info "Writing core/controller.py..."

cat > core/controller.py << 'EOF___EVOCODER_CONTROLLER'
from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
from pathlib import Path
from typing import Optional, AsyncIterator, Callable

from core.schemas import (
    BattleConfig, Task, Submission, Verdict, Lineage,
    Side, JudgeMode, DomainConfig
)
from core.persistence import (
    init_db, get_db, save_task, save_submission, save_verdict, save_lineage,
    get_winning_submission, get_last_round,
    get_submissions_for_round, get_verdicts_for_round, update_leaderboard,
)
from models.model_adapters import make_adapter
from judges.judge import make_judge, BaseJudge
from domains.domain_base import get_domain_registry
from prompts.templates import (
    render_task_prompt, format_verdict_feedback, extract_code_block
)
from sandbox.sandbox import get_sandbox

logger = logging.getLogger("evocoder.controller")


class BattleController:
    """
    The evolutionary round orchestration engine.

    Each round:
    1. Both models receive the task prompt (with feedback from previous round).
    2. Models generate code in parallel.
    3. Judge evaluates both submissions.
    4. Winner is selected; loser's code is archived.
    5. Winner becomes the parent for the next round's mutations.
    6. Feedback is fed back into both models' next prompts.
    """

    def __init__(self, config: BattleConfig, db_path: Path = None):
        if db_path is None:
            db_path = Path("evocoder.db")
        self.config = config
        self.db_path = db_path
        init_db(db_path)
        self.conn = get_db(db_path)

        # Build domain config
        registry = get_domain_registry()
        overrides = config.rules_override or {}
        self.domain = registry.get_or_create(config.domain, **overrides)

        # Build model adapters
        self.side_a = make_adapter(config.side_a_model, config.api_base, config.api_key)
        self.side_b = make_adapter(config.side_b_model, config.api_base, config.api_key)
        self.judge_model = make_adapter(config.judge_model, config.api_base, config.api_key)

        # Build sandbox
        self.sandbox = get_sandbox(enabled=config.judge_mode == JudgeMode.HYBRID)

        # Build judge
        self.judge = make_judge(
            mode=config.judge_mode,
            judge_adapter=self.judge_model,
            sandbox=self.sandbox,
            enable_execution=True,
        )

        # Create task
        self.task = Task(
            description=config.task_description,
            domain=config.domain,
            max_rounds=config.rounds,
            judge_mode=config.judge_mode.value if hasattr(config.judge_mode, 'value') else str(config.judge_mode),
            rules_override=config.rules_override,
        )
        save_task(self.conn, self.task)

        # Track current state
        self.current_round = 0
        self.parent_submission: Optional[Submission] = None
        self.parent_verdict: Optional[Verdict] = None
        self._running = False

    async def run(self) -> AsyncIterator[dict]:
        """Run the full battle. Yields events for streaming to UI."""
        self._running = True
        yield {"type": "battle_start", "task_id": self.task.id, "domain": self.domain.name}

        # Check for continuation (previous rounds in DB)
        last_round = get_last_round(self.conn, self.task.id)
        if last_round > 0:
            self.current_round = last_round
            self.parent_submission = get_winning_submission(self.conn, self.task.id, last_round)
            yield {"type": "continuation", "resumed_from_round": last_round}

        for round_num in range(self.current_round + 1, self.config.rounds + 1):
            if not self._running:
                break

            self.current_round = round_num
            yield {"type": "round_start", "round": round_num}

            # Generate both sides in parallel
            results = await asyncio.gather(
                self._generate_side(Side.A, round_num),
                self._generate_side(Side.B, round_num),
                return_exceptions=True,
            )

            # Handle results
            submissions = []
            for i, result in enumerate(results):
                side = Side.A if i == 0 else Side.B
                if isinstance(result, Exception):
                    logger.error("Side %s generation failed: %s", side, result)
                    yield {"type": "error", "side": side.value, "error": str(result)}
                    sub = Submission(
                        task_id=self.task.id, round=round_num, side=side,
                        model=self.config.side_a_model if side == Side.A else self.config.side_b_model,
                        code="", parent_id=self.parent_submission.id if self.parent_submission else None,
                        generation=round_num,
                    )
                    save_submission(self.conn, sub)
                    submissions.append(sub)
                else:
                    submissions.append(result)
                    yield {
                        "type": "code_generated",
                        "side": side.value,
                        "model": result.model,
                        "round": round_num,
                        "code_preview": result.code[:500],
                    }

            # Judge both submissions
            verdicts = await asyncio.gather(
                self.judge.evaluate(submissions[0], self.domain),
                self.judge.evaluate(submissions[1], self.domain),
                return_exceptions=True,
            )

            for i, v in enumerate(verdicts):
                side = Side.A if i == 0 else Side.B
                if isinstance(v, Exception):
                    logger.error("Judge failed for side %s: %s", side, v)
                    v = Verdict(
                        submission_id=submissions[i].id, task_id=self.task.id,
                        round=round_num, score=0.0, passed=False,
                        reasoning=f"Judge error: {v}",
                    )
                save_verdict(self.conn, v)
                yield {
                    "type": "verdict",
                    "side": side.value,
                    "round": round_num,
                    "score": v.score,
                    "passed": v.passed,
                    "reasoning": v.reasoning[:500],
                    "banned_hits": v.banned_hits,
                    "compile_success": v.compile_success,
                    "test_success": v.test_success,
                }

            # Ensure we have proper Verdict objects
            v_a = verdicts[0] if isinstance(verdicts[0], Verdict) else Verdict(
                submission_id=submissions[0].id, task_id=self.task.id,
                round=round_num, score=0.0, passed=False, reasoning="Judge failed")
            v_b = verdicts[1] if isinstance(verdicts[1], Verdict) else Verdict(
                submission_id=submissions[1].id, task_id=self.task.id,
                round=round_num, score=0.0, passed=False, reasoning="Judge failed")

            # Select winner
            winner_idx = 0 if v_a.score >= v_b.score else 1
            winner_side = Side.A if winner_idx == 0 else Side.B
            winner_sub = submissions[winner_idx]
            winner_verdict = [v_a, v_b][winner_idx]
            loser_sub = submissions[1 - winner_idx]
            loser_verdict = [v_a, v_b][1 - winner_idx]

            # Save lineage
            save_lineage(self.conn, Lineage(
                submission_id=winner_sub.id,
                parent_id=self.parent_submission.id if self.parent_submission else None,
                generation=round_num,
                score=winner_verdict.score,
                side=winner_side,
                is_winner=True,
                is_promoted=True,
            ))
            save_lineage(self.conn, Lineage(
                submission_id=loser_sub.id,
                parent_id=self.parent_submission.id if self.parent_submission else None,
                generation=round_num,
                score=loser_verdict.score,
                side=Side.B if winner_side == Side.A else Side.A,
                is_winner=False,
                is_promoted=False,
            ))

            # Update leaderboard
            update_leaderboard(self.conn, winner_sub.model, won=True, score=winner_verdict.score)
            update_leaderboard(self.conn, loser_sub.model, won=False, score=loser_verdict.score)

            # Set winner as parent for next round
            self.parent_submission = winner_sub
            self.parent_verdict = winner_verdict

            yield {
                "type": "round_result",
                "round": round_num,
                "winner": winner_side.value,
                "winner_model": winner_sub.model,
                "winner_score": winner_verdict.score,
                "loser_score": loser_verdict.score,
                "winner_code": winner_sub.code,
            }

            # Check for stability (winner scored 10/10 and no banned hits)
            if winner_verdict.score >= 10.0 and not winner_verdict.banned_hits:
                if winner_verdict.compile_success is not False and winner_verdict.test_success is not False:
                    yield {"type": "stability_reached", "round": round_num, "score": 10.0}
                    break

        # Final result
        if self.parent_submission:
            yield {
                "type": "battle_end",
                "task_id": self.task.id,
                "total_rounds": self.current_round,
                "final_winner": self.parent_submission.model,
                "final_score": self.parent_verdict.score if self.parent_verdict else 0.0,
                "final_code": self.parent_submission.code,
            }

        self._running = False

    def stop(self):
        self._running = False

    async def _generate_side(self, side: Side, round_num: int) -> Submission:
        """Generate code for one side in a round."""
        adapter = self.side_a if side == Side.A else self.side_b
        model_name = self.config.side_a_model if side == Side.A else self.config.side_b_model

        # Gather previous round feedback
        prev_verdict = None
        prev_code = None
        verdict_feedback = None
        opponent_code = None
        opponent_score = None

        if round_num > 1:
            prev_submissions = get_submissions_for_round(self.conn, self.task.id, round_num - 1)
            prev_verdicts = get_verdicts_for_round(self.conn, self.task.id, round_num - 1)

            # Find this side's verdict and code
            for v in prev_verdicts:
                for s in prev_submissions:
                    if v.submission_id == s.id and s.side == side:
                        prev_verdict = v
                        break

            if prev_verdict:
                for s in prev_submissions:
                    if s.side == side:
                        prev_code = s.code
                        break
                verdict_feedback = format_verdict_feedback(prev_verdict)

            # Get opponent's code
            for s in prev_submissions:
                if s.side != side:
                    opponent_code = s.code
                    for v in prev_verdicts:
                        if v.submission_id == s.id:
                            opponent_score = v.score
                            break
                    break

        # Get parent code (winner from previous round)
        parent_code = self.parent_submission.code if self.parent_submission else None

        # Render prompt
        system, user = render_task_prompt(
            domain=self.domain,
            task_description=self.config.task_description,
            round=round_num,
            previous_code=prev_code,
            verdict_feedback=verdict_feedback,
            opponent_code=opponent_code,
            opponent_score=opponent_score,
            parent_code=parent_code,
            generation=round_num,
            dueling=False,
        )

        # Generate
        raw_response = await adapter.complete(system, user)
        code = extract_code_block(raw_response)

        # Save submission
        submission = Submission(
            task_id=self.task.id,
            round=round_num,
            side=side,
            model=model_name,
            code=code,
            prompt=user,
            parent_id=self.parent_submission.id if self.parent_submission else None,
            generation=round_num,
        )
        save_submission(self.conn, submission)
        return submission
EOF

ok "core/controller.py written"

# ============================================================================
# FILE 7: core/meta_agent.py — Self-referential improvement loop
# ============================================================================
info "Writing core/meta_agent.py..."

cat > core/meta_agent.py << 'EOF___EVOCODER_META_AGENT'
from __future__ import annotations

import json
import logging
import sqlite3
import copy
from typing import Optional

from core.schemas import MetaChange, DomainConfig, Side
from core.persistence import (
    save_meta_change, update_meta_change,
    get_submissions_for_round, get_verdicts_for_round,
)
from models.model_adapters import ModelAdapter
from prompts.templates import render_meta_prompt

logger = logging.getLogger("evocoder.meta_agent")


class MetaAgent:
    """
    The meta-agent analyzes round performance and proposes changes to judge rules.

    Lifecycle:
    1. Collect performance data from recent rounds.
    2. Ask the meta-model to analyze trends and propose rule changes.
    3. Apply changes to a copy of the domain config.
    4. Compare fitness before vs. after.
    5. If improved -> promote (keep changes). If not -> revert.
    6. Store the MetaChange record for audit trail.
    """

    def __init__(self, adapter: ModelAdapter, conn: sqlite3.Connection):
        self.adapter = adapter
        self.conn = conn

    async def propose_changes(self, domain: DomainConfig,
                              task_id: str, current_round: int) -> Optional[MetaChange]:
        """Analyze recent rounds and propose changes to domain config."""
        rounds_data = self._collect_round_data(task_id, current_round)
        if len(rounds_data) < 2:
            logger.info("Meta-agent: not enough rounds yet (%d)", len(rounds_data))
            return None

        # Calculate fitness trend
        half = len(rounds_data) // 2 or 1
        first_scores = [r["side_a_score"] + r["side_b_score"] for r in rounds_data[:half]
                        if r["side_a_score"] is not None and r["side_b_score"] is not None]
        second_scores = [r["side_a_score"] + r["side_b_score"] for r in rounds_data[half:]
                         if r["side_a_score"] is not None and r["side_b_score"] is not None]
        avg_first = sum(first_scores) / len(first_scores) if first_scores else 0.0
        avg_second = sum(second_scores) / len(second_scores) if second_scores else 0.0

        system, user = render_meta_prompt(domain, rounds_data, avg_first, avg_second)

        try:
            response = await self.adapter.complete(system, user, temperature=0.2)
            response = response.strip()
            if response.startswith("```"):
                lines = response.split("\n")
                response = "\n".join(lines[1:-1]) if lines[-1].startswith("```") else "\n".join(lines[1:])

            result = json.loads(response)
            changes = result.get("changes", [])
            if not changes:
                logger.info("Meta-agent: no changes proposed")
                return None

            patch = json.dumps(changes, indent=2)
            summary = result.get("summary", "No summary provided")

            mc = MetaChange(
                task_id=task_id,
                round=current_round,
                target_file="domain_config",
                patch=patch,
                reasoning=summary,
                fitness_before=avg_second,
            )
            save_meta_change(self.conn, mc)
            logger.info("Meta-agent proposed %d changes: %s", len(changes), summary)
            return mc

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            logger.error("Meta-agent parse error: %s", e)
            return None

    def apply_changes(self, domain: DomainConfig, mc: MetaChange) -> DomainConfig:
        """Apply proposed changes to the domain config (returns a new copy)."""
        new_domain = copy.deepcopy(domain)

        try:
            changes = json.loads(mc.patch)
        except json.JSONDecodeError:
            return domain

        for change in changes:
            field = change.get("field", "")
            action = change.get("action", "")
            value = change.get("value", "")
            reasoning = change.get("reasoning", "")

            if field == "banned_patterns":
                if action == "add" and value not in new_domain.banned_patterns:
                    new_domain.banned_patterns.append(value)
                elif action == "remove" and value in new_domain.banned_patterns:
                    new_domain.banned_patterns.remove(value)
                elif action == "replace":
                    new_domain.banned_patterns = value if isinstance(value, list) else [value]

            elif field == "reward_patterns":
                if action == "add" and value not in new_domain.reward_patterns:
                    new_domain.reward_patterns.append(value)
                elif action == "remove" and value in new_domain.reward_patterns:
                    new_domain.reward_patterns.remove(value)
                elif action == "replace":
                    new_domain.reward_patterns = value if isinstance(value, list) else [value]

            elif field == "rubric":
                if action in ("replace", "add"):
                    new_domain.rubric = value

            elif field == "extra_context":
                if action in ("replace", "add"):
                    new_domain.extra_context = value

            logger.info("Applied: %s %s on %s - %s", action, field, str(value)[:50], reasoning)

        update_meta_change(self.conn, mc.id, applied=1)
        return new_domain

    def evaluate_fitness_delta(self, mc: MetaChange, post_fitness: float) -> bool:
        """Compare fitness before and after. Returns True if change should be promoted."""
        mc.fitness_after = post_fitness
        delta = post_fitness - mc.fitness_before
        should_promote = delta >= 0.5

        update_meta_change(
            self.conn, mc.id,
            promoted=1 if should_promote else 0,
            fitness_after=post_fitness,
        )

        if should_promote:
            logger.info("PROMOTED: %.2f -> %.2f (d%.2f)", mc.fitness_before, post_fitness, delta)
        else:
            logger.info("REVERTED: %.2f -> %.2f (d%.2f)", mc.fitness_before, post_fitness, delta)

        return should_promote

    def _collect_round_data(self, task_id: str, current_round: int,
                            lookback: int = 6) -> list[dict]:
        """Collect performance data from recent rounds for the meta-agent."""
        rounds_data = []
        start_round = max(1, current_round - lookback + 1)

        for r in range(start_round, current_round + 1):
            submissions = get_submissions_for_round(self.conn, task_id, r)
            verdicts = get_verdicts_for_round(self.conn, task_id, r)

            if not submissions or not verdicts:
                continue

            side_a_sub = next((s for s in submissions if s.side == Side.A), None)
            side_b_sub = next((s for s in submissions if s.side == Side.B), None)
            side_a_v = next((v for v in verdicts if v.submission_id == (side_a_sub.id if side_a_sub else "")), None)
            side_b_v = next((v for v in verdicts if v.submission_id == (side_b_sub.id if side_b_sub else "")), None)

            winner = "A" if side_a_v and side_b_v and side_a_v.score >= side_b_v.score else "B"

            rounds_data.append({
                "round": r,
                "side_a_model": side_a_sub.model if side_a_sub else "unknown",
                "side_a_score": side_a_v.score if side_a_v else None,
                "side_a_issues": ", ".join(side_a_v.missing_patterns) if side_a_v else "",
                "side_b_model": side_b_sub.model if side_b_sub else "unknown",
                "side_b_score": side_b_v.score if side_b_v else None,
                "side_b_issues": ", ".join(side_b_v.missing_patterns) if side_b_v else "",
                "winner": winner,
            })

        return rounds_data
EOF

ok "core/meta_agent.py written"

# ============================================================================
# FILE 8: domains/domain_base.py — Domain registry and plugin loader
# ============================================================================
info "Writing domains/domain_base.py..."

cat > domains/domain_base.py << 'EOF___EVOCODER_DOMAIN_BASE'
from __future__ import annotations

import logging
import importlib
from typing import Optional

from core.schemas import DomainConfig

logger = logging.getLogger("evocoder.domains")


class DomainRegistry:
    """
    Singleton registry for domain plugins.
    Stores DomainConfig instances keyed by domain name.
    Supports runtime overrides for per-battle customization.
    """

    _instance: Optional["DomainRegistry"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._domains = {}
            cls._instance._loaded = False
        return cls._instance

    def register(self, config: DomainConfig) -> None:
        """Register a domain configuration."""
        self._domains[config.name] = config
        logger.info("Registered domain: %s (%s)", config.name, config.language)

    def get(self, name: str) -> Optional[DomainConfig]:
        """Get a registered domain by name."""
        self._ensure_loaded()
        return self._domains.get(name)

    def list_domains(self) -> list[str]:
        """List all registered domain names."""
        self._ensure_loaded()
        return sorted(self._domains.keys())

    def get_or_create(self, name: str, **overrides) -> DomainConfig:
        """
        Get a domain by name, applying any runtime overrides.
        If the domain doesn't exist, creates a generic one with overrides.
        """
        self._ensure_loaded()

        if name in self._domains:
            domain = self._domains[name]
        else:
            logger.warning("Domain '%s' not found, using generic", name)
            domain = self._domains.get("generic", DomainConfig())

        # Apply overrides (returns a copy to avoid mutating the registered domain)
        import copy
        result = copy.deepcopy(domain)

        if "banned_patterns" in overrides and overrides["banned_patterns"]:
            result.banned_patterns = overrides["banned_patterns"]
        if "reward_patterns" in overrides and overrides["reward_patterns"]:
            result.reward_patterns = overrides["reward_patterns"]
        if "rubric" in overrides and overrides["rubric"]:
            result.rubric = overrides["rubric"]

        return result

    def _ensure_loaded(self) -> None:
        """Load built-in domains if not already loaded."""
        if not self._loaded:
            try:
                from domains.builtin_domains import load_builtin_domains
                load_builtin_domains(self)
            except ImportError as e:
                logger.error("Failed to load builtin domains: %s", e)
            self._loaded = True


def get_domain_registry() -> DomainRegistry:
    """Get the singleton DomainRegistry instance."""
    return DomainRegistry()
EOF

ok "domains/domain_base.py written"

# ============================================================================
# FILE 9: domains/builtin_domains.py — 8 built-in domain configurations
# ============================================================================
info "Writing domains/builtin_domains.py..."

cat > domains/builtin_domains.py << 'EOF___EVOCODER_BUILTIN_DOMAINS'
from __future__ import annotations

from core.schemas import DomainConfig


def load_builtin_domains(registry) -> None:
    """Register all built-in domain configurations."""

    # ─── Generic (no language-specific rules) ───
    registry.register(DomainConfig(
        name="generic",
        language="any",
        rubric="Evaluate code quality, correctness, best practices, and completeness.",
        file_extension=".txt",
        extra_context="Write clean, production-ready code.",
    ))

    # ─── Python ───
    registry.register(DomainConfig(
        name="python",
        language="python",
        banned_patterns=[
            r"\bprint\s*\(",
            r"\bpdb\b",
            r"\bos\.system\b",
        ],
        reward_patterns=[
            r"\basync\s+def\b",
            r"\btry\s*:",
            r'""".*?"""',  # docstrings
            r"\bif\s+__name__\s*==\s*["\']__main__["\']\s*:",
        ],
        rubric=(
            "Python code must be well-structured with proper error handling, "
            "type hints where appropriate, docstrings for public functions, "
            "and follow PEP 8 conventions. Use async/await for I/O operations. "
            "Avoid bare except clauses. Prefer context managers."
        ),
        file_extension=".py",
        extra_context="Write idiomatic Python 3.10+ code with proper error handling.",
        compile_cmd="python3 -m py_compile {file}",
        test_cmd="python3 -m pytest {file} -v --tb=short 2>&1 || true",
    ))

    # ─── Rust ───
    registry.register(DomainConfig(
        name="rust",
        language="rust",
        banned_patterns=[
            r"\bprintln!\s*\"",
            r"\bunwrap\s*\(\s*\)",
        ],
        reward_patterns=[
            r"\basync\s+fn\b",
            r"\bResult\s*<",
            r"#\[test\]",
            r"\bimpl\s+",
            r"\bmatch\s+",
        ],
        rubric=(
            "Rust code must use proper error handling (Result/Option, no unwrap), "
            "follow idiomatic patterns, include tests where applicable, and use "
            "appropriate lifetimes and generics. Prefer ? operator over unwrap."
        ),
        file_extension=".rs",
        extra_context="Write idiomatic Rust code. No unwrap() calls.",
    ))

    # ─── Web (HTML/JS) ───
    registry.register(DomainConfig(
        name="web",
        language="html",
        banned_patterns=[
            r"\balert\s*\(",
            r"\bconsole\.log\b",
            r"\bdocument\.write\b",
        ],
        reward_patterns=[
            r"\basync\s+function\b",
            r"\bfetch\s*\(",
            r"\baria-",
            r"\bsemantic\b",
            r"<main\b",
        ],
        rubric=(
            "Web code must be accessible (ARIA labels, semantic HTML), "
            "use modern JavaScript (async/await, fetch API), be responsive, "
            "and follow best practices for security (no inline scripts, XSS prevention)."
        ),
        file_extension=".html",
        extra_context="Write modern, accessible HTML5 + JavaScript. No alert() or console.log().",
    ))

    # ─── Android SAF (Storage Access Framework) ───
    registry.register(DomainConfig(
        name="android_saf",
        language="java",
        banned_patterns=[
            r"\bjava\.io\.File\b",
            r"\bgetExternalStorageDirectory\b",
            r"\bgetExternalFilesDir\b",
            r"\bEnvironment\b.*\bgetExternal\b",
        ],
        reward_patterns=[
            r"\bMediaStore\b",
            r"\bDocumentFile\b",
            r"\bContentResolver\b",
            r"\bACTION_OPEN_DOCUMENT\b",
            r"\bACTION_CREATE_DOCUMENT\b",
            r"\bgetContentUri\b",
        ],
        rubric=(
            "Android code must use the Storage Access Framework (SAF) for file access. "
            "No direct java.io.File or external storage paths. Use DocumentFile, "
            "ContentResolver, and MediaStore APIs. Handle permissions properly."
        ),
        file_extension=".java",
        extra_context="Write Android code using Storage Access Framework. No java.io.File or getExternalStorageDirectory.",
    ))

    # ─── C++ ───
    registry.register(DomainConfig(
        name="cpp",
        language="cpp",
        banned_patterns=[
            r"\bnew\s*\[",
            r"\bmalloc\s*\(",
            r"\bprintf\s*\(",
            r"\bfree\s*\(",
        ],
        reward_patterns=[
            r"\bconstexpr\b",
            r"\bRAII\b",
            r"\bstd::unique_ptr\b",
            r"\bstd::shared_ptr\b",
            r"\bstd::make_unique\b",
            r"\bstd::make_shared\b",
            r"#include\s*<memory>",
        ],
        rubric=(
            "C++ code must use RAII, smart pointers (no raw new/delete), "
            "constexpr where possible, proper include guards, and follow "
            "modern C++17/20 conventions. No malloc/free or printf."
        ),
        file_extension=".cpp",
        extra_context="Write modern C++17 code with RAII and smart pointers. No malloc or printf.",
    ))

    # ─── Dockerfile ───
    registry.register(DomainConfig(
        name="dockerfile",
        language="dockerfile",
        banned_patterns=[
            r":latest\b",
            r"chmod\s+777",
            r"\bapt-get\s+upgrade\b",
            r"\bUSER\s+root\b",
        ],
        reward_patterns=[
            r"\bUSER\s+(?!root\b)",
            r"\bHEALTHCHECK\b",
            r"multi-stage",
            r"FROM\s+\S+\s+AS\s+",
            r"\b--no-cache\b",
            r"\b\.dockerignore\b",
        ],
        rubric=(
            "Dockerfile must follow best practices: pin specific image tags (no :latest), "
            "use multi-stage builds, define a non-root USER, add HEALTHCHECK, "
            "use --no-cache for package installs, and minimize layer count."
        ),
        file_extension=".dockerfile",
        extra_context="Write a production-ready Dockerfile. No :latest tags or chmod 777.",
    ))

    # ─── Shell (Bash) ───
    registry.register(DomainConfig(
        name="shell",
        language="bash",
        banned_patterns=[
            r"\brm\s+-rf\s+/",
            r"\beval\s+["\']",
            r"\bset\s+\+e\b",
        ],
        reward_patterns=[
            r"\bset\s+-euo\s+pipefail\b",
            r"\btrap\s+",
            r"\bgetopts\b",
            r"\blocal\s+",
            r"\breadonly\s+",
        ],
        rubric=(
            "Shell scripts must use 'set -euo pipefail', proper error handling with trap, "
            "quoted variables, getopts for argument parsing, local variables in functions, "
            "and no dangerous rm -rf or eval commands."
        ),
        file_extension=".sh",
        extra_context="Write safe, robust Bash scripts with set -euo pipefail.",
    ))
EOF

ok "domains/builtin_domains.py written"

# ============================================================================
# FILE 10: prompts/templates.py — Jinja2 prompt templates
# ============================================================================
info "Writing prompts/templates.py..."

cat > prompts/templates.py << 'EOF___EVOCODER_TEMPLATES'
from __future__ import annotations

import re
from jinja2 import Template
from typing import Optional
from core.schemas import DomainConfig, Verdict, Submission

# ─── Task Agent Templates ───

TASK_AGENT_SYSTEM = Template("""You are an expert {{ domain.language }} developer in a competitive coding arena.
Domain: {{ domain.name }}
Language: {{ domain.language }}
{{ domain.extra_context }}
Rules:
1. Output ONLY code in a single fenced code block. No explanations.
2. If you receive feedback from a previous round, address ALL issues.
3. Do not reintroduce patterns that were previously flagged as banned.
4. Your code must be complete and production-ready.
{% if domain.banned_patterns %}
BANNED patterns (automatic disqualification):
{% for p in domain.banned_patterns %}- {{ p }}
{% endfor %}
{% endif %}
{% if domain.reward_patterns %}
REWARDED patterns (boost your score):
{% for p in domain.reward_patterns %}- {{ p }}
{% endfor %}
{% endif %}
""")

TASK_AGENT_USER = Template("""## Task
{{ task_description }}
{% if previous_code %}
## Your Previous Submission (Round {{ round - 1 }})
```
{{ previous_code }}
```
{% endif %}
{% if verdict_feedback %}
## Judge Feedback from Round {{ round - 1 }}
{{ verdict_feedback }}
You MUST address all issues above. Do not repeat the same mistakes.
{% endif %}
{% if opponent_code and dueling %}
## Opponent Submission (Round {{ round - 1 }})
```
{{ opponent_code }}
```
Your opponent scored {{ opponent_score if opponent_score else 'N/A' }}/10. Beat them.
{% endif %}
{% if parent_code and round > 1 %}
## Parent Code (Best from Generation {{ generation - 1 }})
```
{{ parent_code }}
```
Improve upon this code. Do not regress.
{% endif %}
Output your {{ domain.language }} code in a single fenced code block. Nothing else.""")

# ─── Judge Templates ───

JUDGE_SYSTEM = Template("""You are an expert code judge evaluating {{ domain.language }} code.
Apply this rubric strictly:
{{ domain.rubric or "Evaluate code quality, correctness, best practices, and completeness." }}
Return a JSON object with:
  "score": float (0.0 to 10.0),
  "passed": boolean,
  "reasoning": string,
  "issues": list of strings,
  "strengths": list of strings
Return ONLY the JSON object.""")

JUDGE_USER = Template("""## Rubric
{{ domain.rubric or "Evaluate code quality, correctness, best practices, and completeness." }}
## Submitted Code
```
{{ code }}
```
Evaluate this code. Return JSON only.""")

# ─── Meta-Agent Templates ───

META_AGENT_SYSTEM = Template("""You are a meta-agent that improves the evaluation system of a competitive coding arena.
You analyze performance data and propose changes to:
1. Judge rules (banned/reward patterns, rubric text)
2. Prompt templates
Output a JSON object:
{
  "target": "domain_config",
  "changes": [
    {
      "field": "banned_patterns" | "reward_patterns" | "rubric" | "extra_context",
      "action": "add" | "remove" | "replace",
      "value": "...",
      "reasoning": "..."
    }
  ],
  "summary": "Brief explanation of why these changes should improve fitness"
}
Return ONLY the JSON object.""")

META_AGENT_USER = Template("""## Domain: {{ domain.name }} ({{ domain.language }})
## Current Domain Configuration
- Banned patterns: {{ domain.banned_patterns }}
- Reward patterns: {{ domain.reward_patterns }}
- Rubric: {{ domain.rubric }}
- Extra context: {{ domain.extra_context }}
## Performance History (Last {{ rounds|length }} rounds)
{% for r in rounds %}
### Round {{ r.round }}
- Side A ({{ r.side_a_model }}): Score {{ r.side_a_score }}/10
  - Issues: {{ r.side_a_issues }}
- Side B ({{ r.side_b_model }}): Score {{ r.side_b_score }}/10
  - Issues: {{ r.side_b_issues }}
- Winner: {{ r.winner }}
{% endfor %}
## Fitness Trend
- Average score round 1-{{ half }}: {{ avg_first_half }}
- Average score round {{ half + 1 }}-{{ rounds|length }}: {{ avg_second_half }}
- Trend: {{ "improving" if avg_second_half > avg_first_half else "declining or flat" }}
## Task
Analyze the performance data. Are the judge rules catching real issues?
Propose changes to improve evaluation quality.
Return JSON only.""")


# ─── Helper Functions ───

def extract_code_block(text: str) -> str:
    """Extract code from a fenced code block. Returns the text as-is if no fence."""
    matches = re.findall(r'```(?:\w+)?\n(.*?)```', text, re.DOTALL)
    if matches:
        return matches[0].strip()
    return text.strip()


def format_verdict_feedback(verdict: Verdict) -> str:
    """Format a verdict into a human-readable feedback string for the next round prompt."""
    parts = ["Score: " + str(verdict.score) + "/10"]
    if verdict.banned_hits:
        parts.append("BANNED: " + ", ".join(verdict.banned_hits))
    if verdict.missing_patterns:
        parts.append("Missing: " + ", ".join(verdict.missing_patterns))
    if verdict.reward_hits:
        parts.append("Good: " + ", ".join(verdict.reward_hits))
    if verdict.compile_success is False:
        parts.append("COMPILATION FAILED: " + verdict.compile_output[:200])
    elif verdict.compile_success is True:
        parts.append("Compilation passed.")
    if verdict.test_success is False:
        parts.append("TESTS FAILED: " + verdict.test_output[:200])
    elif verdict.test_success is True:
        parts.append("Tests passed.")
    if verdict.reasoning:
        parts.append("Judge: " + verdict.reasoning)
    return "\n".join(parts)


def render_task_prompt(domain: DomainConfig, task_description: str,
                      round: int, previous_code: str = None,
                      verdict_feedback: str = None, opponent_code: str = None,
                      opponent_score: float = None, parent_code: str = None,
                      generation: int = 0, dueling: bool = False) -> tuple[str, str]:
    """Render the system and user prompts for a task agent."""
    system = TASK_AGENT_SYSTEM.render(domain=domain)
    user = TASK_AGENT_USER.render(
        domain=domain, task_description=task_description,
        round=round, previous_code=previous_code,
        verdict_feedback=verdict_feedback,
        opponent_code=opponent_code if dueling else None,
        opponent_score=opponent_score if dueling else None,
        parent_code=parent_code, generation=generation, dueling=dueling,
    )
    return system.strip(), user.strip()


def render_judge_prompt(domain: DomainConfig, code: str) -> tuple[str, str]:
    """Render the system and user prompts for the LLM judge."""
    system = JUDGE_SYSTEM.render(domain=domain)
    user = JUDGE_USER.render(domain=domain, code=code)
    return system.strip(), user.strip()


def render_meta_prompt(domain: DomainConfig, rounds_data: list,
                       avg_first_half: float, avg_second_half: float) -> tuple[str, str]:
    """Render the system and user prompts for the meta-agent."""
    half = len(rounds_data) // 2 if rounds_data else 0
    system = META_AGENT_SYSTEM.render()
    user = META_AGENT_USER.render(
        domain=domain, rounds=rounds_data, half=half,
        avg_first_half=avg_first_half, avg_second_half=avg_second_half,
    )
    return system.strip(), user.strip()
EOF

ok "prompts/templates.py written"

# ============================================================================
# FILE 11: sandbox/sandbox.py — Docker-based code execution sandbox
# ============================================================================
info "Writing sandbox/sandbox.py..."

cat > sandbox/sandbox.py << 'EOF___EVOCODER_SANDBOX'
from __future__ import annotations

import asyncio
import tempfile
import os
from typing import Optional

try:
    import docker as docker_sync
    HAS_DOCKER = True
except ImportError:
    HAS_DOCKER = False

SANDBOX_IMAGE = "evocoder-sandbox:latest"
TIMEOUT_SECONDS = 30
MAX_OUTPUT = 4096


class DockerSandbox:
    """
    Docker-based isolated code execution sandbox.
    Runs code in a container with no network, memory limits, and timeout.
    """

    def __init__(self, image: str = SANDBOX_IMAGE,
                 timeout: int = TIMEOUT_SECONDS,
                 max_output: int = MAX_OUTPUT,
                 memory_limit: str = "512m",
                 cpu_limit: int = 1):
        self.image = image
        self.timeout = timeout
        self.max_output = max_output
        self.memory_limit = memory_limit
        self.cpu_limit = cpu_limit
        self._available = self._check_docker()

    def _check_docker(self) -> bool:
        if HAS_DOCKER:
            try:
                client = docker_sync.from_env()
                client.ping()
                return True
            except Exception:
                return False
        return False

    @property
    def available(self) -> bool:
        return self._available

    async def run_code(self, code: str, file_extension: str,
                       compile_cmd: str = None,
                       test_cmd: str = None) -> dict:
        """
        Execute code in a sandboxed container.
        Returns dict with compile_success, test_success, compile_output, test_output.
        """
        if not self._available:
            return {
                "compile_success": None,
                "test_success": None,
                "compile_output": "Docker not available.",
                "test_output": "",
            }

        with tempfile.TemporaryDirectory() as tmpdir:
            filename = f"submission{file_extension}"
            filepath = os.path.join(tmpdir, filename)
            with open(filepath, "w") as f:
                f.write(code)

            compile_output = ""
            test_output = ""
            compile_success = None
            test_success = None

            if compile_cmd:
                cmd = compile_cmd.replace("{file}", f"/workspace/{filename}")
                try:
                    result = await self._exec_in_container(cmd, tmpdir)
                    compile_output = result["output"][:self.max_output]
                    compile_success = result["exit_code"] == 0
                except Exception as e:
                    compile_output = str(e)
                    compile_success = False

            if test_cmd and compile_success is not False:
                cmd = test_cmd.replace("{file}", f"/workspace/{filename}")
                try:
                    result = await self._exec_in_container(cmd, tmpdir)
                    test_output = result["output"][:self.max_output]
                    test_success = result["exit_code"] == 0
                except Exception as e:
                    test_output = str(e)
                    test_success = False

            return {
                "compile_success": compile_success,
                "test_success": test_success,
                "compile_output": compile_output,
                "test_output": test_output,
            }

    async def _exec_in_container(self, cmd: str, mount_dir: str) -> dict:
        """Run a command in a Docker container and return output + exit code."""
        loop = asyncio.get_event_loop()

        def _run():
            client = docker_sync.from_env()
            try:
                container = client.containers.run(
                    self.image,
                    command=["sh", "-c", cmd],
                    volumes={os.path.abspath(mount_dir): {"bind": "/workspace", "mode": "ro"}},
                    working_dir="/workspace",
                    mem_limit=self.memory_limit,
                    cpu_quota=int(self.cpu_limit * 100000),
                    network_mode="none",
                    detach=True,
                    stderr=True,
                    stdout=True,
                )
                try:
                    result = container.wait(timeout=self.timeout)
                    logs = container.logs().decode("utf-8", errors="replace")
                    return {"output": logs, "exit_code": result.get("StatusCode", -1)}
                finally:
                    container.remove(force=True)
            except Exception as e:
                return {"output": str(e), "exit_code": -1}
            finally:
                client.close()

        return await loop.run_in_executor(None, _run)


class NullSandbox:
    """No-op sandbox for when Docker is not available."""

    @property
    def available(self) -> bool:
        return False

    async def run_code(self, *args, **kwargs) -> dict:
        return {
            "compile_success": None,
            "test_success": None,
            "compile_output": "Sandbox disabled.",
            "test_output": "",
        }


def get_sandbox(enabled: bool = True):
    """Factory: returns DockerSandbox if available, else NullSandbox."""
    if not enabled:
        return NullSandbox()
    sandbox = DockerSandbox()
    return sandbox if sandbox.available else NullSandbox()
EOF

ok "sandbox/sandbox.py written"

# ============================================================================
# FILE 12: main.py — FastAPI + WebSocket server
# ============================================================================
info "Writing main.py..."

cat > main.py << 'EOF___EVOCODER_MAIN'
from __future__ import annotations

import asyncio
import json
import os
import logging
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from core.schemas import BattleConfig, JudgeMode
from core.controller import BattleController
from core.meta_agent import MetaAgent
from core.persistence import (
    init_db, get_db, get_leaderboard,
    get_continuation_context, get_meta_changes, get_lineage_tree,
)
from domains.domain_base import get_domain_registry

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
logger = logging.getLogger("evocoder")

# Initialize DB
init_db()


# ─── Pydantic request models ───

class BattleRequest(BaseModel):
    task_description: str = Field(..., description="The task to evolve code for")
    domain: str = Field("generic", description="Domain plugin name")
    side_a_model: str = Field("qwen2-coder:14b")
    side_b_model: str = Field("mistral:8x7b-instruct")
    judge_model: str = Field("qwen3-coder:30b")
    meta_model: str = Field("", description="Meta-agent model. Empty = disabled")
    rounds: int = Field(5, ge=1, le=50)
    judge_mode: str = Field("hybrid", description="static | llm | hybrid")
    enable_meta: bool = Field(False, description="Enable self-referential improvement")
    meta_interval: int = Field(3, description="Run meta-agent every N rounds")
    banned_patterns: Optional[list[str]] = None
    reward_patterns: Optional[list[str]] = None
    rubric: Optional[str] = None
    api_base: str = Field("http://localhost:11434/v1")
    api_key: str = Field("")


class RegisterTopicRequest(BaseModel):
    topic: str


# ─── App setup ───

app = FastAPI(title="EvoCoder", description="Autonomous Evolutionary Coding Engine")

STATIC_DIR = Path(__file__).parent / "static"
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

TOPIC_CACHE: dict[str, str] = {}


# ─── REST Endpoints ───

@app.get("/")
async def index():
    """Serve the web UI."""
    f = STATIC_DIR / "index.html"
    if f.exists():
        return HTMLResponse(f.read_text())
    return HTMLResponse("<h1>EvoCoder</h1><p>Web UI not found.</p>")


@app.get("/api/domains")
async def list_domains():
    """List all available domain plugins."""
    registry = get_domain_registry()
    out = []
    for name in registry.list_domains():
        d = registry.get(name)
        if d:
            out.append({
                "name": name,
                "language": d.language,
                "file_extension": d.file_extension,
            })
    return {"domains": out}


@app.get("/api/leaderboard")
async def leaderboard():
    """Get the model leaderboard."""
    conn = get_db()
    board = get_leaderboard(conn)
    conn.close()
    return {"leaderboard": board}


@app.get("/api/continuation")
async def continuation(task_id: str):
    """Get continuation context for a task."""
    conn = get_db()
    ctx = get_continuation_context(conn)
    conn.close()
    return ctx


@app.get("/api/meta_changes/{task_id}")
async def meta_changes(task_id: str):
    """Get meta-agent change history for a task."""
    conn = get_db()
    changes = get_meta_changes(conn, task_id)
    conn.close()
    return {"changes": changes}


@app.get("/api/lineage/{task_id}")
async def lineage(task_id: str):
    """Get the evolutionary lineage tree for a task."""
    conn = get_db()
    tree = get_lineage_tree(conn, task_id)
    conn.close()
    return {"lineage": tree}


@app.post("/api/register_topic")
async def register_topic(req: RegisterTopicRequest):
    """Register a large topic and return a short token for WebSocket startup."""
    import uuid
    token = uuid.uuid4().hex[:16]
    TOPIC_CACHE[token] = req.topic
    return {"token": token}


@app.get("/api/health")
async def health():
    return {"status": "ok", "version": "2.0.0"}


# ─── WebSocket: Live Battle Stream ───

@app.websocket("/ws/battle")
async def ws_battle(websocket: WebSocket):
    """WebSocket endpoint for live battle streaming."""
    await websocket.accept()
    controller = None
    try:
        raw = await websocket.receive_text()
        data = json.loads(raw)

        # Check for topic token
        if "token" in data and data["token"] in TOPIC_CACHE:
            data["task_description"] = TOPIC_CACHE.pop(data["token"])

        # Build rules override
        rules_override = {}
        if data.get("banned_patterns"):
            rules_override["banned_patterns"] = data["banned_patterns"]
        if data.get("reward_patterns"):
            rules_override["reward_patterns"] = data["reward_patterns"]
        if data.get("rubric"):
            rules_override["rubric"] = data["rubric"]

        config = BattleConfig(
            task_description=data["task_description"],
            domain=data.get("domain", "generic"),
            side_a_model=data.get("side_a_model", "qwen2-coder:14b"),
            side_b_model=data.get("side_b_model", "mistral:8x7b-instruct"),
            judge_model=data.get("judge_model", "qwen3-coder:30b"),
            meta_model=data.get("meta_model", ""),
            rounds=data.get("rounds", 5),
            judge_mode=JudgeMode(data.get("judge_mode", "hybrid")),
            enable_meta=data.get("enable_meta", False),
            meta_interval=data.get("meta_interval", 3),
            rules_override=rules_override or None,
            api_base=data.get("api_base", "http://localhost:11434/v1"),
            api_key=data.get("api_key", ""),
        )

        controller = BattleController(config)

        if config.enable_meta and config.meta_model:
            # Meta-agent enabled: interleave meta-analysis between rounds
            from models.model_adapters import make_adapter as _ma
            meta_adapter = _ma(config.meta_model, config.api_base, config.api_key)
            meta = MetaAgent(meta_adapter, controller.conn)

            async for event in controller.run():
                await websocket.send_text(json.dumps(event, default=str))

                if (event.get("type") == "round_result" and
                    event.get("round", 0) % config.meta_interval == 0):
                    await websocket.send_text(json.dumps({
                        "type": "meta_agent_start",
                        "round": event["round"],
                    }))

                    mc = await meta.propose_changes(
                        controller.domain,
                        controller.task.id,
                        event["round"],
                    )
                    if mc:
                        new_domain = meta.apply_changes(controller.domain, mc)
                        post_fitness = event.get("winner_score", 0.0)
                        should_promote = meta.evaluate_fitness_delta(mc, post_fitness)

                        await websocket.send_text(json.dumps({
                            "type": "meta_agent_result",
                            "round": event["round"],
                            "change_id": mc.id,
                            "promoted": should_promote,
                            "fitness_before": mc.fitness_before,
                            "fitness_after": post_fitness,
                            "summary": mc.reasoning,
                        }))

                        if should_promote:
                            controller.domain = new_domain
        else:
            # Standard battle without meta-agent
            async for event in controller.run():
                await websocket.send_text(json.dumps(event, default=str))

        await websocket.send_text(json.dumps({"type": "complete"}))

    except WebSocketDisconnect:
        logger.info("WebSocket disconnected")
    except Exception as e:
        logger.error("WebSocket error: %s", e, exc_info=True)
        try:
            await websocket.send_text(json.dumps({"type": "error", "message": str(e)}))
        except Exception:
            pass
    finally:
        if controller and hasattr(controller, "conn"):
            try:
                controller.conn.close()
            except Exception:
                pass


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

ok "main.py written"

# ============================================================================
# FILE 13: static/index.html — Web UI
# ============================================================================
info "Writing static/index.html..."

cat > static/index.html << 'EOF___EVOCODER_INDEX_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>EvoCoder</title>
<style>
:root{
  --bg:#0d1117;--surface:#161b22;--border:#30363d;--text:#e6edf3;
  --text-dim:#8b949e;--accent:#58a6ff;--accent-dim:#1f6feb;
  --success:#3fb950;--danger:#f85149;--warning:#d29922;
  --side-a:#58a6ff;--side-b:#bc8cff;--meta:#d29922
}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',monospace;
  background:var(--bg);color:var(--text);font-size:14px;line-height:1.6}
.header{padding:16px 24px;border-bottom:1px solid var(--border);
  display:flex;align-items:center;gap:12px}
.header h1{font-size:20px}
.header .tag{font-size:11px;padding:2px 8px;border-radius:4px;
  background:var(--accent-dim);color:var(--text);text-transform:uppercase;letter-spacing:.5px}
.container{display:grid;grid-template-columns:320px 1fr 320px;gap:1px;
  height:calc(100vh - 57px)}
.panel{background:var(--surface);overflow-y:auto;padding:16px}
.panel-title{font-size:12px;text-transform:uppercase;color:var(--text-dim);
  letter-spacing:1px;margin-bottom:12px;border-bottom:1px solid var(--border);
  padding-bottom:8px}
.form-group{margin-bottom:12px}
.form-group label{display:block;font-size:12px;color:var(--text-dim);margin-bottom:4px}
.form-group input,.form-group select,.form-group textarea{
  width:100%;padding:8px 10px;background:var(--bg);border:1px solid var(--border);
  border-radius:6px;color:var(--text);font-size:13px;font-family:inherit}
.form-group textarea{resize:vertical;min-height:80px}
.form-group input:focus,.form-group select:focus,.form-group textarea:focus{
  outline:none;border-color:var(--accent)}
.model-pair{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.toggle{display:flex;align-items:center;gap:8px;margin-bottom:12px}
.toggle input[type="checkbox"]{width:16px;height:16px;accent-color:var(--accent)}
.toggle label{font-size:12px;color:var(--text-dim)}
.btn-primary{width:100%;padding:12px;background:var(--accent-dim);color:var(--text);
  border:none;border-radius:6px;font-size:14px;font-weight:600;cursor:pointer}
.btn-primary:hover{background:var(--accent)}
.btn-primary:disabled{opacity:.5;cursor:not-allowed}
.btn-secondary{width:100%;padding:8px;background:transparent;color:var(--text-dim);
  border:1px solid var(--border);border-radius:6px;font-size:12px;
  cursor:pointer;margin-top:8px}
.btn-secondary:hover{border-color:var(--accent)}
.round-header{font-size:14px;font-weight:600;color:var(--text-dim);
  padding:8px 0;border-bottom:1px solid var(--border)}
.round-header span{color:var(--accent)}
.card{background:var(--bg);border:1px solid var(--border);
  border-radius:8px;padding:12px}
.card.a-side{border-top:3px solid var(--side-a)}
.card.b-side{border-top:3px solid var(--side-b)}
.card-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}
.card-title{font-size:13px;font-weight:600}
.card-score{font-size:18px;font-weight:700;padding:2px 10px;border-radius:4px}
.card-score.high{color:var(--success)}
.card-score.mid{color:var(--warning)}
.card-score.low{color:var(--danger)}
.card-model{font-size:11px;color:var(--text-dim);margin-bottom:8px}
.card-verdict{font-size:12px;color:var(--text-dim)}
.card-banned{color:var(--danger);font-weight:600}
.card-code{margin-top:8px;background:var(--surface);border-radius:6px;padding:10px;
  font-family:'Fira Code','Monaco',monospace;font-size:11px;max-height:300px;
  overflow-y:auto;white-space:pre-wrap;color:var(--text-dim)}
.meta-banner{background:rgba(210,153,34,.1);border:1px solid var(--meta);
  border-radius:6px;padding:10px;font-size:12px;color:var(--meta)}
.meta-banner .promoted{color:var(--success)}
.meta-banner .reverted{color:var(--danger)}
.status-bar{padding:8px 12px;background:var(--surface);border-radius:6px;
  font-size:12px;color:var(--text-dim)}
.sidebar-section{margin-bottom:20px}
.leaderboard-item{display:flex;justify-content:space-between;padding:6px 0;
  border-bottom:1px solid var(--border);font-size:12px}
.leaderboard-item .model{color:var(--text)}
.leaderboard-item .elo{color:var(--accent);font-weight:600}
.lineage-item{font-size:11px;padding:4px 0;border-bottom:1px solid var(--border)}
.lineage-item .winner{color:var(--success)}
.spinner{display:inline-block;width:14px;height:14px;border:2px solid var(--border);
  border-top-color:var(--accent);border-radius:50%;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.loading{display:flex;align-items:center;gap:8px;color:var(--text-dim);font-size:12px}
</style>
</head>
<body>
<div class="header">
  <h1>EvoCoder</h1>
  <span class="tag">Autonomous Evolutionary Coding Engine</span>
</div>
<div class="container">
  <!-- ─── Config Panel ─── -->
  <div class="panel" id="config-panel">
    <div class="panel-title">Battle Configuration</div>
    <div class="form-group">
      <label>Task Description</label>
      <textarea id="task-description" placeholder="Write a Python async web scraper with retry logic..."></textarea>
    </div>
    <div class="form-group">
      <label>Domain</label>
      <select id="domain-select">
        <option value="generic">Generic</option>
      </select>
    </div>
    <div class="form-group">
      <label>Side A Model</label>
      <input type="text" id="side-a-model" value="qwen2-coder:14b">
    </div>
    <div class="form-group">
      <label>Side B Model</label>
      <input type="text" id="side-b-model" value="mistral:8x7b-instruct">
    </div>
    <div class="form-group">
      <label>Judge Model</label>
      <input type="text" id="judge-model" value="qwen3-coder:30b">
    </div>
    <div class="model-pair">
      <div class="form-group">
        <label>Rounds</label>
        <input type="number" id="rounds" value="5" min="1" max="50">
      </div>
      <div class="form-group">
        <label>Judge Mode</label>
        <select id="judge-mode">
          <option value="hybrid">Hybrid</option>
          <option value="llm">LLM Only</option>
          <option value="static">Static Only</option>
        </select>
      </div>
    </div>
    <div class="toggle">
      <input type="checkbox" id="enable-meta">
      <label>Enable Meta-Agent</label>
    </div>
    <div class="form-group" id="meta-model-group" style="display:none">
      <label>Meta-Agent Model</label>
      <input type="text" id="meta-model" value="qwen3-coder:30b">
    </div>
    <div class="form-group">
      <label>API Base URL</label>
      <input type="text" id="api-base" value="http://localhost:11434/v1">
    </div>
    <div class="form-group">
      <label>API Key</label>
      <input type="password" id="api-key" placeholder="empty for local">
    </div>
    <button class="btn-primary" id="start-btn" onclick="startBattle()">START BATTLE</button>
    <button class="btn-secondary" onclick="loadLeaderboard()">Refresh Leaderboard</button>
    <button class="btn-secondary" onclick="loadDomains()">Load Domains</button>
  </div>

  <!-- ─── Arena Panel ─── -->
  <div class="panel" id="arena-panel">
    <div class="panel-title">Live Arena</div>
    <div id="arena-content">
      <div class="status-bar">Configure a battle and press START.</div>
    </div>
  </div>

  <!-- ─── Sidebar ─── -->
  <div class="panel" id="sidebar">
    <div class="sidebar-section">
      <div class="panel-title">Leaderboard</div>
      <div id="leaderboard-content">
        <div class="loading"><span class="spinner"></span> Loading...</div>
      </div>
    </div>
    <div class="sidebar-section">
      <div class="panel-title">Lineage Tree</div>
      <div id="lineage-content">
        <div style="color:var(--text-dim);font-size:12px">No data yet.</div>
      </div>
    </div>
    <div class="sidebar-section">
      <div class="panel-title">Meta-Agent Log</div>
      <div id="meta-log">
        <div style="color:var(--text-dim);font-size:12px">Inactive.</div>
      </div>
    </div>
  </div>
</div>

<script>
let ws = null;
let currentBattleData = {};

window.addEventListener('load', () => {
  loadDomains();
  loadLeaderboard();
  document.getElementById('enable-meta').addEventListener('change', e => {
    document.getElementById('meta-model-group').style.display = e.target.checked ? 'block' : 'none';
  });
});

async function loadDomains() {
  try {
    const r = await fetch('/api/domains');
    const d = await r.json();
    const s = document.getElementById('domain-select');
    s.innerHTML = '<option value="generic">Generic</option>';
    if (d.domains) {
      d.domains.forEach(x => {
        const o = document.createElement('option');
        o.value = x.name;
        o.textContent = x.name + ' (' + x.language + ')';
        s.appendChild(o);
      });
    }
  } catch(e) { console.error('loadDomains:', e); }
}

async function loadLeaderboard() {
  try {
    const r = await fetch('/api/leaderboard');
    const d = await r.json();
    const c = document.getElementById('leaderboard-content');
    if (!d.leaderboard || !d.leaderboard.length) {
      c.innerHTML = '<div style="color:var(--text-dim);font-size:12px">No battles yet.</div>';
      return;
    }
    c.innerHTML = d.leaderboard.map((i, n) =>
      '<div class="leaderboard-item"><span class="model">#' + (n+1) + ' ' +
      i.model + '</span><span class="elo">' +
      (i.elo_rating || 1200).toFixed(0) + ' ELO</span></div>'
    ).join('');
  } catch(e) { console.error('loadLeaderboard:', e); }
}

function startBattle() {
  const task = document.getElementById('task-description').value.trim();
  if (!task) { alert('Enter a task'); return; }

  const config = {
    task_description: task,
    domain: document.getElementById('domain-select').value,
    side_a_model: document.getElementById('side-a-model').value,
    side_b_model: document.getElementById('side-b-model').value,
    judge_model: document.getElementById('judge-model').value,
    meta_model: document.getElementById('enable-meta').checked ?
      document.getElementById('meta-model').value : '',
    rounds: parseInt(document.getElementById('rounds').value),
    judge_mode: document.getElementById('judge-mode').value,
    enable_meta: document.getElementById('enable-meta').checked,
    api_base: document.getElementById('api-base').value,
    api_key: document.getElementById('api-key').value,
  };

  if (task.length > 50000) {
    fetch('/api/register_topic', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({topic: task})
    }).then(r => r.json()).then(d => {
      config.token = d.token;
      delete config.task_description;
      connectWebSocket(config);
    });
  } else {
    connectWebSocket(config);
  }
}

function connectWebSocket(config) {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(proto + '//' + location.host + '/ws/battle');
  document.getElementById('start-btn').disabled = true;
  document.getElementById('start-btn').textContent = 'BATTLE IN PROGRESS...';
  document.getElementById('arena-content').innerHTML = '';

  ws.onopen = () => ws.send(JSON.stringify(config));
  ws.onmessage = e => handleEvent(JSON.parse(e.data));
  ws.onclose = () => {
    document.getElementById('start-btn').disabled = false;
    document.getElementById('start-btn').textContent = 'START BATTLE';
  };
  ws.onerror = () => {
    document.getElementById('start-btn').disabled = false;
    document.getElementById('start-btn').textContent = 'START BATTLE';
  };
}

function handleEvent(d) {
  const a = document.getElementById('arena-content');

  switch (d.type) {
    case 'battle_start':
      a.innerHTML = '<div class="status-bar">Battle started - Domain: ' +
        d.domain + ' - Task: ' + d.task_id + '</div>';
      currentBattleData = {taskId: d.task_id};
      break;

    case 'continuation':
      a.innerHTML += '<div class="status-bar">Resuming from round ' +
        d.resumed_from_round + '</div>';
      break;

    case 'round_start':
      a.innerHTML += '<div class="round-header">Round <span>' +
        d.round + '</span></div>';
      break;

    case 'code_generated':
      var sk = d.side.toLowerCase();
      var c = document.createElement('div');
      c.className = 'card ' + sk + '-side';
      c.id = 'round-' + d.round + '-side-' + sk;
      c.innerHTML =
        '<div class="card-header"><div class="card-title">Side ' + d.side +
        '</div><div class="loading"><span class="spinner"></span> Generating...</div></div>' +
        '<div class="card-model">' + d.model + '</div>' +
        '<pre class="card-code">' + escapeHtml(d.code_preview) + '...</pre>';
      a.appendChild(c);
      break;

    case 'verdict':
      updateCard(d);
      break;

    case 'round_result':
      var r = document.createElement('div');
      r.className = 'status-bar';
      r.innerHTML = 'Round ' + d.round + ' Winner: <strong style="color:var(--side-' +
        d.winner.toLowerCase() + ')">Side ' + d.winner + '</strong> (' +
        d.winner_model + ') - ' + d.winner_score + '/10 vs ' + d.loser_score + '/10';
      a.appendChild(r);
      loadLeaderboard();
      break;

    case 'meta_agent_start':
      var m = document.createElement('div');
      m.className = 'meta-banner';
      m.id = 'meta-' + d.round;
      m.innerHTML = 'Meta-agent analyzing...';
      a.appendChild(m);
      break;

    case 'meta_agent_result':
      var ml = document.getElementById('meta-log');
      var e = document.createElement('div');
      e.className = 'lineage-item';
      e.innerHTML = 'Round ' + d.round + ': ' +
        (d.promoted ? '<span class="winner">PROMOTED</span>' : 'REVERTED') +
        ' - d' + (d.fitness_after - d.fitness_before).toFixed(2);
      ml.appendChild(e);

      var mb = document.getElementById('meta-' + d.round);
      if (mb) {
        mb.innerHTML = 'Meta-agent ' +
          (d.promoted ? '<span class="promoted">PROMOTED</span>' :
            '<span class="reverted">REVERTED</span>') +
          ' - ' + d.fitness_before.toFixed(1) + ' -> ' +
          d.fitness_after.toFixed(1) + ' - ' + d.summary;
      }
      break;

    case 'stability_reached':
      a.innerHTML += '<div class="status-bar" style="color:var(--success)">' +
        'STABILITY at round ' + d.round + ' - score ' + d.score + '/10</div>';
      break;

    case 'battle_end':
      var ed = document.createElement('div');
      ed.className = 'status-bar';
      ed.style.borderColor = 'var(--success)';
      ed.innerHTML = 'Battle complete - ' + d.total_rounds +
        ' rounds - Winner: ' + d.final_winner + ' (' + d.final_score +
        '/10)<br><br><button class="btn-secondary" onclick="copyCode()">Copy Code</button>' +
        '<button class="btn-secondary" onclick="downloadCode()">Download</button>';
      a.appendChild(ed);
      currentBattleData.finalCode = d.final_code;
      break;

    case 'error':
      a.innerHTML += '<div class="status-bar" style="color:var(--danger)">' +
        'Error: ' + (d.message || d.error) + '</div>';
      break;

    case 'complete':
      document.getElementById('start-btn').disabled = false;
      document.getElementById('start-btn').textContent = 'START BATTLE';
      break;
  }

  a.scrollTop = a.scrollHeight;
}

function updateCard(d) {
  var sk = d.side.toLowerCase();
  var c = document.getElementById('round-' + d.round + '-side-' + sk);
  if (!c) return;

  var sc = d.score >= 7 ? 'high' : d.score >= 4 ? 'mid' : 'low';
  var sh = '<div class="card-score ' + sc + '">' + d.score + '/10</div>';

  var vh = '<div class="card-verdict">' + d.reasoning + '</div>';
  if (d.banned_hits && d.banned_hits.length) {
    vh += '<div class="card-banned">BANNED: ' + d.banned_hits.join(', ') + '</div>';
  }
  if (d.compile_success === false) {
    vh += '<div class="card-banned">COMPILATION FAILED</div>';
  } else if (d.compile_success === true) {
    vh += '<div style="color:var(--success)">Compiled</div>';
  }
  if (d.test_success === true) {
    vh += '<div style="color:var(--success)">Tests passed</div>';
  } else if (d.test_success === false) {
    vh += '<div class="card-banned">Tests failed</div>';
  }

  var loadingEl = c.querySelector('.loading');
  if (loadingEl) loadingEl.innerHTML = sh;

  var existingVerdict = c.querySelector('.card-verdict');
  if (existingVerdict) existingVerdict.remove();
  c.innerHTML += vh;
}

function escapeHtml(t) {
  var d = document.createElement('div');
  d.textContent = t;
  return d.innerHTML;
}

function copyCode() {
  if (currentBattleData.finalCode) {
    navigator.clipboard.writeText(currentBattleData.finalCode);
    alert('Copied!');
  }
}

function downloadCode() {
  if (currentBattleData.finalCode) {
    var b = new Blob([currentBattleData.finalCode], {type: 'text/plain'});
    var a = document.createElement('a');
    a.href = URL.createObjectURL(b);
    a.download = 'winning_code.txt';
    a.click();
  }
}
</script>
</body>
</html>
EOF

ok "static/index.html written"

# ============================================================================
# FILE 14: requirements.txt
# ============================================================================
info "Writing requirements.txt..."

cat > requirements.txt << 'EOF___EVOCODER_REQUIREMENTS'
# ─── Core ───
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
httpx>=0.25.0
jinja2>=3.1.0
pydantic>=2.0.0

# ─── Database ───
# sqlite3 is built-in, no extra package needed

# ─── Docker (optional — for sandboxed code execution) ───
docker>=7.0.0

# ─── Dev ───
pytest>=7.0.0
pytest-asyncio>=0.21.0
EOF

ok "requirements.txt written"

# ============================================================================
# FILE 15: Dockerfile (sandbox image)
# ============================================================================
info "Writing Dockerfile..."

cat > Dockerfile << 'EOF___EVOCODER_DOCKERFILE'
# ─── EvoCoder Sandbox Image ───
# Lightweight container for compiling and testing model-generated code.
# Build: docker build --network=host -t evocoder-sandbox .

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install common language runtimes
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev \
    gcc g++ cmake make \
    rustc cargo \
    openjdk-17-jdk-headless \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Python testing tools
RUN pip3 install --no-cache-dir pytest

# Non-root user for safety
RUN useradd -m -s /bin/bash coder
USER coder
WORKDIR /workspace

# Default: just keep container alive
CMD ["sleep", "infinity"]
EOF

ok "Dockerfile written"

# ============================================================================
# FILE 16: README.md
# ============================================================================
info "Writing README.md..."

cat > README.md << 'EOF___EVOCODER_README'
# EvoCoder — Autonomous Evolutionary Coding Engine

Two LLMs enter. One survives. The judge evolves. No human babysitting required.

EvoCoder is a competitive, self-improving multi-agent coding platform.
Two LLMs battle to produce the best code for any task, a judge evaluates
their output, and feedback is fed back into the next round. Winners become
parents for the next generation. An optional meta-agent rewrites the judge's
own rules over time — making the system self-referential.

## Architecture

    evocoder/
    ├── core/
    │   ├── schemas.py          # Data models (Task, Submission, Verdict, Lineage, MetaChange)
    │   ├── persistence.py      # SQLite layer with lineage tracking, continuation, leaderboard
    │   ├── controller.py       # Round orchestration, model dispatch, parent selection
    │   └── meta_agent.py       # Self-referential improvement loop
    ├── domains/
    │   ├── domain_base.py      # Domain registry and plugin loader
    │   └── builtin_domains.py  # Built-in: Python, Rust, Web, Android SAF, C++, Dockerfile, Shell
    ├── judges/
    │   └── judge.py            # StaticJudge, LLMJudge, HybridJudge
    ├── models/
    │   └── model_adapters.py   # OpenAI-compatible async adapter (Ollama, vLLM, OpenAI, etc.)
    ├── prompts/
    │   └── templates.py        # Jinja2-based dynamic prompt generation
    ├── sandbox/
    │   └── sandbox.py          # Docker-based code execution sandbox
    ├── static/
    │   └── index.html           # Web UI (WebSocket live streaming)
    ├── main.py                 # FastAPI + WebSocket server
    ├── requirements.txt
    ├── Dockerfile              # Sandbox image for code execution
    └── README.md

## Quick Start

### 1. Install

    chmod +x install.sh
    ./install.sh

### 2. (Optional) Build sandbox Docker image

    cd evocoder
    docker build -t evocoder-sandbox .

Without Docker, the system still works — code execution checks are skipped,
and judging falls back to static + LLM only.

### 3. Run the server

    cd evocoder
    source venv/bin/activate
    python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000

Open http://localhost:8000 in your browser.

### 4. Configure a battle

1. Enter your task description.
2. Select a domain (or use "generic" for any language).
3. Choose your models (Side A, Side B, Judge).
4. Optionally enable the Meta-Agent for self-referential improvement.
5. Press START BATTLE.

## Built-in Domains

| Domain | Language | Banned | Rewarded | Compile | Test |
|--------|----------|--------|----------|---------|------|
| generic | any | — | — | — | — |
| python | Python | print(), pdb, os.system | async def, try:, docstrings | py_compile | pytest |
| rust | Rust | println!, unwrap() | async fn, Result, #[test] | — | — |
| web | HTML/JS | alert(), console.log | async, fetch, aria | — | — |
| android_saf | Java | java.io.File, getExternalStorageDirectory | SAF patterns | — | — |
| cpp | C++ | new[], malloc, printf | constexpr, RAII, smart pointers | — | — |
| dockerfile | Dockerfile | :latest, chmod 777 | USER, HEALTHCHECK, multi-stage | — | — |
| shell | Bash | rm -rf /, eval | set -euo, trap, getopts | — | — |

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| / | GET | Web UI |
| /api/domains | GET | List available domain plugins |
| /api/leaderboard | GET | Model ELO rankings |
| /api/continuation | GET | Get continuation context for a task |
| /api/meta_changes/{task_id} | GET | Meta-agent change history |
| /api/lineage/{task_id} | GET | Evolutionary lineage tree |
| /api/register_topic | POST | Register large topic (returns token for WebSocket) |
| /api/health | GET | Health check |
| /ws/battle | WebSocket | Live battle streaming |

## License

MIT
EOF

ok "README.md written"

# ============================================================================
# ─── Virtual Environment & Dependencies ───
# ============================================================================
info "Setting up Python virtual environment..."

python3 -m venv venv
source venv/bin/activate

info "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

ok "Dependencies installed"

# ============================================================================
# ─── Optional: Build Docker Sandbox Image ───
# ============================================================================
if [ "${HAS_DOCKER}" = true ]; then
    info "Building Docker sandbox image..."
    if docker build -t "${SANDBOX_IMAGE}" . 2>/dev/null; then
        ok "Docker sandbox image built: ${SANDBOX_IMAGE}"
    else
        warn "Docker sandbox build failed. You can build it later with:"
        warn "  docker build -t ${SANDBOX_IMAGE} ."
    fi
else
    info "Skipping Docker sandbox build (Docker not available)"
    info "To enable sandbox code execution, install Docker and run:"
    info "  docker build -t ${SANDBOX_IMAGE} ."
fi

# ============================================================================
# ─── Summary ───
# ============================================================================
echo ""
echo "=============================================="
echo "  EvoCoder v${SCRIPT_VERSION} — Installation Complete"
echo "=============================================="
echo ""
echo "  Target directory: ${TARGET_DIR}"
echo "  Virtual env:       ${TARGET_DIR}/venv"
echo "  Database:          ${TARGET_DIR}/evocoder.db (created on first run)"
echo ""
echo "  To start the server:"
echo "    cd ${TARGET_DIR}"
echo "    source venv/bin/activate"
echo "    python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
echo ""
echo "  Then open: http://localhost:8000"
echo ""
if [ "${HAS_DOCKER}" = true ]; then
    echo "  Docker sandbox: ${SANDBOX_IMAGE} (ready)"
else
    echo "  Docker sandbox: not built (code execution disabled)"
    echo "  The system works without it — judging uses static + LLM only."
fi
echo ""
ok "Done!"
