#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# EvoCoder — Autonomous Evolutionary Coding Engine
# Full project installer script. Creates all directories and files.
# Usage: bash setup_evocoder.sh
# ═══════════════════════════════════════════════════════════════

PROJECT_DIR="evocoder"

echo "🧬 Creating EvoCoder project in ./$PROJECT_DIR ..."

# ─── Directory structure ───
mkdir -p "$PROJECT_DIR"/{core,domains,judges,models,prompts,sandbox,static}

# ─── __init__.py files ───
cat > "$PROJECT_DIR/__init__.py"           << 'PYEOF'
# EvoCoder — Autonomous Evolutionary Coding Engine
PYEOF

cat > "$PROJECT_DIR/core/__init__.py"      << 'PYEOF'
# EvoCoder core package
PYEOF

cat > "$PROJECT_DIR/domains/__init__.py"   << 'PYEOF'
# Domain plugins
PYEOF

cat > "$PROJECT_DIR/judges/__init__.py"    << 'PYEOF'
# Judge system
PYEOF

cat > "$PROJECT_DIR/models/__init__.py"    << 'PYEOF'
# Model adapters
PYEOF

cat > "$PROJECT_DIR/prompts/__init__.py"   << 'PYEOF'
# Prompt templates
PYEOF

cat > "$PROJECT_DIR/sandbox/__init__.py"   << 'PYEOF'
# Sandbox system
PYEOF

# ─── requirements.txt ───
cat > "$PROJECT_DIR/requirements.txt" << 'TXTEOF'
# Core
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
httpx>=0.25.0
jinja2>=3.1.0
pydantic>=2.0.0

# Database
# sqlite3 is built-in, no extra package needed

# Docker (optional — for sandboxed code execution)
docker>=7.0.0

# Dev
pytest>=7.0.0
pytest-asyncio>=0.21.0
TXTEOF

# ─── Dockerfile ───
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE'
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
DOCKERFILE

# ─── core/schemas.py ───
cat > "$PROJECT_DIR/core/schemas.py" << 'PYEOF'
"""
Core data schemas for EvoCoder — the autonomous evolutionary coding engine.
"""
from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


def _uid() -> str:
    return uuid.uuid4().hex[:12]


class Side(str, Enum):
    A = "A"
    B = "B"
    META = "META"  # meta-agent side


class JudgeMode(str, Enum):
    STATIC = "static"    # regex-only fast-fail
    LLM = "llm"         # LLM-as-judge with rubric
    HYBRID = "hybrid"    # static fast-fail + LLM rubric + optional execution


@dataclass
class DomainConfig:
    """Pluggable domain configuration. Ships as a plugin or defined at runtime."""
    name: str                                   # "python", "rust", "android_saf"
    language: str                                # primary language for output
    banned_patterns: list[str] = field(default_factory=list)      # regex patterns that auto-fail
    reward_patterns: list[str] = field(default_factory=list)      # regex patterns that boost score
    rubric: str = ""                             # natural-language rubric for LLM judge
    compile_cmd: Optional[str] = None            # e.g., "python -m py_compile {file}"
    test_cmd: Optional[str] = None               # e.g., "pytest {file} -v"
    file_extension: str = ".py"                  # output file extension
    extra_context: str = ""                      # domain-specific preamble for prompts


@dataclass
class Task:
    id: str = field(default_factory=_uid)
    description: str = ""                        # the actual task prompt
    domain: str = "generic"                      # domain plugin name
    created_at: float = field(default_factory=time.time)
    max_rounds: int = 10
    judge_mode: JudgeMode = JudgeMode.HYBRID
    rules_override: Optional[dict] = None        # runtime rule overrides (banned/reward/rubric)


@dataclass
class Submission:
    id: str = field(default_factory=_uid)
    task_id: str = ""
    round: int = 0
    side: Side = Side.A
    model: str = ""                              # model identifier
    code: str = ""                               # the generated artifact
    prompt: str = ""                             # the prompt that produced this (for lineage)
    parent_id: Optional[str] = None              # parent submission in lineage tree
    generation: int = 0                          # evolutionary generation number
    created_at: float = field(default_factory=time.time)


@dataclass
class Verdict:
    id: str = field(default_factory=_uid)
    submission_id: str = ""
    task_id: str = ""
    round: int = 0
    score: float = 0.0                          # 0.0 to 10.0
    passed: bool = False
    reasoning: str = ""                         # judge explanation
    banned_hits: list[str] = field(default_factory=list)
    reward_hits: list[str] = field(default_factory=list)
    missing_patterns: list[str] = field(default_factory=list)
    compile_success: Optional[bool] = None       # None if not attempted
    test_success: Optional[bool] = None           # None if not attempted
    compile_output: str = ""
    test_output: str = ""
    created_at: float = field(default_factory=time.time)


@dataclass
class Lineage:
    """Tracks the evolutionary tree of submissions."""
    id: str = field(default_factory=_uid)
    submission_id: str = ""
    parent_id: Optional[str] = None
    generation: int = 0
    score: float = 0.0
    side: Side = Side.A
    is_winner: bool = False                      # won its round
    is_promoted: bool = False                    # became parent for next gen


@dataclass
class BattleConfig:
    """Configuration for a single battle (evolution run)."""
    task_description: str
    domain: str = "generic"
    side_a_model: str = "qwen2-coder:14b"
    side_b_model: str = "mistral:8x7b-instruct"
    judge_model: str = "qwen3-coder:30b"
    meta_model: str = ""                         # empty = meta-agent disabled
    rounds: int = 5
    judge_mode: JudgeMode = JudgeMode.HYBRID
    enable_meta: bool = False                    # enable self-referential improvement
    meta_interval: int = 3                        # run meta-agent every N rounds
    rules_override: Optional[dict] = None
    api_base: str = "http://localhost:11434/v1"  # OpenAI-compatible base URL
    api_key: str = ""                             # optional API key


@dataclass
class MetaChange:
    """A proposed change from the meta-agent to judge/domain rules."""
    id: str = field(default_factory=_uid)
    task_id: str = ""
    round: int = 0
    target_file: str = ""                        # which file to patch
    patch: str = ""                               # unified diff or full replacement
    reasoning: str = ""
    applied: bool = False
    promoted: bool = False                       # change improved fitness and was kept
    fitness_before: float = 0.0
    fitness_after: float = 0.0
    created_at: float = field(default_factory=time.time)
PYEOF

# ─── core/persistence.py ───
cat > "$PROJECT_DIR/core/persistence.py" << 'PYEOF'
"""
SQLite persistence layer for EvoCoder.
Handles sessions, submissions, verdicts, lineage, and continuation.
"""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Optional

from .schemas import Submission, Verdict, Lineage, Task, MetaChange, Side, BattleConfig


DB_PATH = Path("evocoder.db")


def get_db(db_path: Path = DB_PATH) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db(db_path: Path = DB_PATH) -> None:
    conn = get_db(db_path)
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        domain TEXT DEFAULT 'generic',
        created_at REAL,
        max_rounds INTEGER DEFAULT 10,
        judge_mode TEXT DEFAULT 'hybrid',
        rules_override TEXT
    );

    CREATE TABLE IF NOT EXISTS battles (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        config TEXT NOT NULL,
        created_at REAL,
        status TEXT DEFAULT 'running',
        current_round INTEGER DEFAULT 0,
        FOREIGN KEY (task_id) REFERENCES tasks(id)
    );

    CREATE TABLE IF NOT EXISTS submissions (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        battle_id TEXT,
        round INTEGER NOT NULL,
        side TEXT NOT NULL,
        model TEXT,
        code TEXT,
        prompt TEXT,
        parent_id TEXT,
        generation INTEGER DEFAULT 0,
        created_at REAL
    );

    CREATE TABLE IF NOT EXISTS verdicts (
        id TEXT PRIMARY KEY,
        submission_id TEXT NOT NULL,
        task_id TEXT NOT NULL,
        round INTEGER,
        score REAL,
        passed INTEGER,
        reasoning TEXT,
        banned_hits TEXT,
        reward_hits TEXT,
        missing_patterns TEXT,
        compile_success INTEGER,
        test_success INTEGER,
        compile_output TEXT,
        test_output TEXT,
        created_at REAL,
        FOREIGN KEY (submission_id) REFERENCES submissions(id)
    );

    CREATE TABLE IF NOT EXISTS lineages (
        id TEXT PRIMARY KEY,
        submission_id TEXT NOT NULL,
        parent_id TEXT,
        generation INTEGER,
        score REAL,
        side TEXT,
        is_winner INTEGER DEFAULT 0,
        is_promoted INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS meta_changes (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        round INTEGER,
        target_file TEXT,
        patch TEXT,
        reasoning TEXT,
        applied INTEGER DEFAULT 0,
        promoted INTEGER DEFAULT 0,
        fitness_before REAL,
        fitness_after REAL,
        created_at REAL
    );

    CREATE TABLE IF NOT EXISTS leaderboard (
        model TEXT PRIMARY KEY,
        wins INTEGER DEFAULT 0,
        losses INTEGER DEFAULT 0,
        total_score REAL DEFAULT 0,
        battles INTEGER DEFAULT 0,
        avg_score REAL DEFAULT 0,
        elo_rating REAL DEFAULT 1000.0
    );

    CREATE INDEX IF NOT EXISTS idx_submissions_task ON submissions(task_id);
    CREATE INDEX IF NOT EXISTS idx_submissions_battle ON submissions(battle_id);
    CREATE INDEX IF NOT EXISTS idx_verdicts_submission ON verdicts(submission_id);
    CREATE INDEX IF NOT EXISTS idx_lineages_submission ON lineages(submission_id);
    """)
    conn.commit()
    conn.close()


# ─── Tasks ───

def save_task(conn: sqlite3.Connection, task: Task) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO tasks (id, description, domain, created_at, max_rounds, judge_mode, rules_override) VALUES (?,?,?,?,?,?,?)",
        (task.id, task.description, task.domain, task.created_at, task.max_rounds, task.judge_mode.value, json.dumps(task.rules_override) if task.rules_override else None)
    )
    conn.commit()


def load_task(conn: sqlite3.Connection, task_id: str) -> Optional[Task]:
    row = conn.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone()
    if not row:
        return None
    return Task(
        id=row["id"], description=row["description"], domain=row["domain"],
        created_at=row["created_at"], max_rounds=row["max_rounds"],
        judge_mode=row["judge_mode"],
        rules_override=json.loads(row["rules_override"]) if row["rules_override"] else None
    )


# ─── Submissions ───

def save_submission(conn: sqlite3.Connection, sub: Submission) -> None:
    conn.execute(
        "INSERT INTO submissions (id, task_id, battle_id, round, side, model, code, prompt, parent_id, generation, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        (sub.id, sub.task_id, None, sub.round, sub.side.value, sub.model, sub.code, sub.prompt, sub.parent_id, sub.generation, sub.created_at)
    )
    conn.commit()


def get_submissions_for_round(conn: sqlite3.Connection, task_id: str, round: int) -> list[Submission]:
    rows = conn.execute("SELECT * FROM submissions WHERE task_id=? AND round=? ORDER BY side", (task_id, round)).fetchall()
    return [_row_to_submission(r) for r in rows]


def get_latest_submissions(conn: sqlite3.Connection, task_id: str, limit: int = 2) -> list[Submission]:
    """Get the most recent submissions for continuation."""
    rows = conn.execute(
        "SELECT * FROM submissions WHERE task_id=? ORDER BY round DESC, side LIMIT ?", (task_id, limit)
    ).fetchall()
    return [_row_to_submission(r) for r in rows]


def get_winning_submission(conn: sqlite3.Connection, task_id: str, round: int) -> Optional[Submission]:
    """Get the winning submission for a round via lineage."""
    row = conn.execute(
        """SELECT s.* FROM submissions s
           JOIN lineages l ON s.id = l.submission_id
           WHERE s.task_id=? AND s.round=? AND l.is_winner=1
           LIMIT 1""",
        (task_id, round)
    ).fetchone()
    return _row_to_submission(row) if row else None


def _row_to_submission(row: sqlite3.Row) -> Submission:
    return Submission(
        id=row["id"], task_id=row["task_id"], round=row["round"],
        side=Side(row["side"]), model=row["model"], code=row["code"],
        prompt=row["prompt"], parent_id=row["parent_id"],
        generation=row["generation"], created_at=row["created_at"]
    )


# ─── Verdicts ───

def save_verdict(conn: sqlite3.Connection, v: Verdict) -> None:
    conn.execute(
        """INSERT INTO verdicts (id, submission_id, task_id, round, score, passed, reasoning,
           banned_hits, reward_hits, missing_patterns, compile_success, test_success,
           compile_output, test_output, created_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (v.id, v.submission_id, v.task_id, v.round, v.score, int(v.passed), v.reasoning,
         json.dumps(v.banned_hits), json.dumps(v.reward_hits), json.dumps(v.missing_patterns),
         v.compile_success, v.test_success, v.compile_output, v.test_output, v.created_at)
    )
    conn.commit()


def get_verdicts_for_round(conn: sqlite3.Connection, task_id: str, round: int) -> list[Verdict]:
    rows = conn.execute("SELECT * FROM verdicts WHERE task_id=? AND round=?", (task_id, round)).fetchall()
    return [_row_to_verdict(r) for r in rows]


def get_latest_verdicts(conn: sqlite3.Connection, task_id: str, limit: int = 2) -> list[Verdict]:
    rows = conn.execute(
        "SELECT * FROM verdicts WHERE task_id=? ORDER BY round DESC LIMIT ?", (task_id, limit)
    ).fetchall()
    return [_row_to_verdict(r) for r in rows]


def _row_to_verdict(row: sqlite3.Row) -> Verdict:
    return Verdict(
        id=row["id"], submission_id=row["submission_id"], task_id=row["task_id"],
        round=row["round"], score=row["score"], passed=bool(row["passed"]),
        reasoning=row["reasoning"],
        banned_hits=json.loads(row["banned_hits"]) if row["banned_hits"] else [],
        reward_hits=json.loads(row["reward_hits"]) if row["reward_hits"] else [],
        missing_patterns=json.loads(row["missing_patterns"]) if row["missing_patterns"] else [],
        compile_success=bool(row["compile_success"]) if row["compile_success"] is not None else None,
        test_success=bool(row["test_success"]) if row["test_success"] is not None else None,
        compile_output=row["compile_output"] or "",
        test_output=row["test_output"] or "",
        created_at=row["created_at"]
    )


# ─── Lineage ───

def save_lineage(conn: sqlite3.Connection, lin: Lineage) -> None:
    conn.execute(
        "INSERT INTO lineages (id, submission_id, parent_id, generation, score, side, is_winner, is_promoted) VALUES (?,?,?,?,?,?,?,?)",
        (lin.id, lin.submission_id, lin.parent_id, lin.generation, lin.score, lin.side.value, int(lin.is_winner), int(lin.is_promoted))
    )
    conn.commit()


def get_lineage_tree(conn: sqlite3.Connection, task_id: str) -> list[dict]:
    rows = conn.execute(
        """SELECT l.*, s.round, s.model FROM lineages l
           JOIN submissions s ON l.submission_id = s.id
           WHERE s.task_id=? ORDER BY s.round, l.side""",
        (task_id,)
    ).fetchall()
    return [dict(r) for r in rows]


# ─── Meta Changes ───

def save_meta_change(conn: sqlite3.Connection, mc: MetaChange) -> None:
    conn.execute(
        "INSERT INTO meta_changes (id, task_id, round, target_file, patch, reasoning, applied, promoted, fitness_before, fitness_after, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        (mc.id, mc.task_id, mc.round, mc.target_file, mc.patch, mc.reasoning, int(mc.applied), int(mc.promoted), mc.fitness_before, mc.fitness_after, mc.created_at)
    )
    conn.commit()


def update_meta_change(conn: sqlite3.Connection, mc_id: str, **kwargs) -> None:
    sets = ", ".join(f"{k}=?" for k in kwargs)
    conn.execute(f"UPDATE meta_changes SET {sets} WHERE id=?", (*kwargs.values(), mc_id))
    conn.commit()


def get_meta_changes(conn: sqlite3.Connection, task_id: str) -> list[dict]:
    rows = conn.execute("SELECT * FROM meta_changes WHERE task_id=? ORDER BY round", (task_id,)).fetchall()
    return [dict(r) for r in rows]


# ─── Leaderboard ───

def update_leaderboard(conn: sqlite3.Connection, model: str, won: bool, score: float) -> None:
    row = conn.execute("SELECT * FROM leaderboard WHERE model=?", (model,)).fetchone()
    if row:
        wins = row["wins"] + (1 if won else 0)
        losses = row["losses"] + (0 if won else 1)
        total_score = row["total_score"] + score
        battles = row["battles"] + 1
        avg = total_score / battles if battles > 0 else 0.0
        # Simple ELO update
        elo = row["elo_rating"]
        expected = 1.0 / (1.0 + 10 ** ((row["elo_rating"] - 1000) / 400.0))
        elo += 32 * ((1.0 if won else 0.0) - expected)
        conn.execute(
            "UPDATE leaderboard SET wins=?, losses=?, total_score=?, battles=?, avg_score=?, elo_rating=? WHERE model=?",
            (wins, losses, total_score, battles, avg, elo, model)
        )
    else:
        conn.execute(
            "INSERT INTO leaderboard (model, wins, losses, total_score, battles, avg_score, elo_rating) VALUES (?,?,?,?,?,?,?)",
            (model, 1 if won else 0, 0 if won else 1, score, 1, score, 1000.0 + (32 if won else 0))
        )
    conn.commit()


def get_leaderboard(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute("SELECT * FROM leaderboard ORDER BY elo_rating DESC").fetchall()
    return [dict(r) for r in rows]


# ─── Continuation ───

def get_last_round(conn: sqlite3.Connection, task_id: str) -> int:
    row = conn.execute("SELECT MAX(round) as max_round FROM submissions WHERE task_id=?", (task_id,)).fetchone()
    return row["max_round"] if row and row["max_round"] else 0


def get_continuation_context(conn: sqlite3.Connection, task_id: str) -> dict:
    """Get the latest round's submissions + verdicts for continuation."""
    last_round = get_last_round(conn, task_id)
    if last_round == 0:
        return {"round": 0, "submissions": [], "verdicts": []}
    return {
        "round": last_round,
        "submissions": [s.__dict__ for s in get_submissions_for_round(conn, task_id, last_round)],
        "verdicts": [v.__dict__ for v in get_verdicts_for_round(conn, task_id, last_round)],
    }
PYEOF

# ─── models/model_adapters.py ───
cat > "$PROJECT_DIR/models/model_adapters.py" << 'PYEOF'
"""
Model adapters for EvoCoder.
Supports any OpenAI-compatible API (Ollama, vLLM, llama.cpp, OpenAI, OpenRouter, etc.)
"""
from __future__ import annotations

import json
import httpx
import asyncio
from typing import Optional, AsyncIterator


class ModelAdapter:
    """
    Async adapter for OpenAI-compatible chat completion APIs.
    Works with Ollama (http://localhost:11434/v1), vLLM, llama.cpp server, OpenAI, OpenRouter.
    """

    def __init__(
        self,
        model: str,
        api_base: str = "http://localhost:11434/v1",
        api_key: str = "",
        temperature: float = 0.7,
        max_tokens: int = 4096,
        timeout: float = 120.0,
    ):
        self.model = model
        self.api_base = api_base.rstrip("/")
        self.api_key = api_key or "not-needed"
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.timeout = timeout

    async def complete(self, system: str, user: str, temperature: Optional[float] = None) -> str:
        """Single-shot completion. Returns the full response text."""
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature or self.temperature,
            "max_tokens": self.max_tokens,
        }
        headers = {"Content-Type": "application/json"}
        if self.api_key and self.api_key != "not-needed":
            headers["Authorization"] = f"Bearer {self.api_key}"

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.post(
                f"{self.api_base}/chat/completions",
                json=payload,
                headers=headers,
            )
            resp.raise_for_status()
            data = resp.json()
            return data["choices"][0]["message"]["content"]

    async def stream(self, system: str, user: str, temperature: Optional[float] = None) -> AsyncIterator[str]:
        """Streaming completion. Yields content chunks as they arrive."""
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature or self.temperature,
            "max_tokens": self.max_tokens,
            "stream": True,
        }
        headers = {"Content-Type": "application/json"}
        if self.api_key and self.api_key != "not-needed":
            headers["Authorization"] = f"Bearer {self.api_key}"

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            async with client.stream(
                "POST",
                f"{self.api_base}/chat/completions",
                json=payload,
                headers=headers,
            ) as resp:
                resp.raise_for_status()
                async for line in resp.aiter_lines():
                    if not line or line.strip() == "data: [DONE]":
                        continue
                    if line.startswith("data: "):
                        try:
                            chunk = json.loads(line[6:])
                            delta = chunk["choices"][0].get("delta", {})
                            if "content" in delta and delta["content"]:
                                yield delta["content"]
                        except (json.JSONDecodeError, KeyError, IndexError):
                            continue

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass


def make_adapter(model: str, api_base: str = "http://localhost:11434/v1", api_key: str = "", **kwargs) -> ModelAdapter:
    """Factory function to create a model adapter."""
    return ModelAdapter(model=model, api_base=api_base, api_key=api_key, **kwargs)
PYEOF

# ─── judges/judge.py ───
cat > "$PROJECT_DIR/judges/judge.py" << 'PYEOF'
"""
Judge system for EvoCoder.
Three judge types: Static (regex), LLM (rubric-based), Hybrid (static + LLM + optional execution).
"""
from __future__ import annotations

import re
import json
from abc import ABC, abstractmethod
from typing import Optional

from core.schemas import DomainConfig, Verdict, Submission, JudgeMode
from models.model_adapters import ModelAdapter
from sandbox.sandbox import DockerSandbox


class BaseJudge(ABC):
    """Abstract base for all judges."""

    @abstractmethod
    async def evaluate(self, submission: Submission, domain: DomainConfig) -> Verdict:
        ...


class StaticJudge(BaseJudge):
    """Regex-based fast-fail judge. Instant, deterministic, but shallow."""

    async def evaluate(self, submission: Submission, domain: DomainConfig) -> Verdict:
        code = submission.code
        banned_hits = []
        reward_hits = []
        missing = []

        # Check banned patterns → instant fail
        for pattern in domain.banned_patterns:
            if re.search(pattern, code, re.MULTILINE | re.DOTALL):
                banned_hits.append(pattern)

        # Check reward patterns → score boost
        for pattern in domain.reward_patterns:
            if re.search(pattern, code, re.MULTILINE | re.DOTALL):
                reward_hits.append(pattern)
            else:
                missing.append(pattern)

        # Calculate score
        if banned_hits:
            score = 0.0
            passed = False
            reasoning = f"FAILED: Banned patterns detected: {banned_hits}"
        else:
            total_reward = len(domain.reward_patterns) if domain.reward_patterns else 1
            hit_count = len(reward_hits)
            score = round((hit_count / total_reward) * 10.0, 2) if total_reward > 0 else 5.0
            passed = score >= 7.0
            reasoning = f"Static check: {hit_count}/{total_reward} reward patterns matched."

        return Verdict(
            submission_id=submission.id,
            task_id=submission.task_id,
            round=submission.round,
            score=score,
            passed=passed,
            reasoning=reasoning,
            banned_hits=banned_hits,
            reward_hits=reward_hits,
            missing_patterns=missing,
        )


class LLMJudge(BaseJudge):
    """LLM-as-judge: uses a rubric to evaluate code quality. Handles any language/domain."""

    def __init__(self, judge_adapter: ModelAdapter):
        self.adapter = judge_adapter

    async def evaluate(self, submission: Submission, domain: DomainConfig) -> Verdict:
        system_prompt = (
            "You are an expert code judge. Evaluate the submitted code against the rubric. "
            "Return a JSON object with the following fields:\n"
            '  "score": float (0.0 to 10.0),\n'
            '  "passed": boolean (true if score >= 7.0),\n'
            '  "reasoning": string (explanation of the score),\n'
            '  "issues": list of strings (specific problems found),\n'
            '  "strengths": list of strings (what was done well)\n'
            "Return ONLY the JSON object, no other text."
        )

        user_prompt = (
            f"## Task\n{domain.extra_context}\n\n"
            f"## Rubric\n{domain.rubric or 'Evaluate code quality, correctness, best practices, and completeness.'}\n\n"
            f"## Language\n{domain.language}\n\n"
            f"## Submitted Code\n```\n{submission.code}\n```\n\n"
            "Evaluate this code. Return JSON only."
        )

        try:
            response = await self.adapter.complete(system_prompt, user_prompt, temperature=0.1)
            # Extract JSON from response (handles markdown code fences)
            response = response.strip()
            if response.startswith("```"):
                lines = response.split("\n")
                response = "\n".join(lines[1:-1]) if lines[-1].startswith("```") else "\n".join(lines[1:])

            result = json.loads(response)
            return Verdict(
                submission_id=submission.id,
                task_id=submission.task_id,
                round=submission.round,
                score=float(result.get("score", 0.0)),
                passed=result.get("passed", False),
                reasoning=result.get("reasoning", ""),
                banned_hits=[],
                reward_hits=[],
                missing_patterns=result.get("issues", []),
            )
        except (json.JSONDecodeError, KeyError, ValueError) as e:
            return Verdict(
                submission_id=submission.id,
                task_id=submission.task_id,
                round=submission.round,
                score=0.0,
                passed=False,
                reasoning=f"LLM judge parse error: {e}",
            )


class HybridJudge(BaseJudge):
    """
    Hybrid judge: static regex fast-fail → LLM rubric scoring → optional Docker execution.
    Best of all worlds: instant bans, nuanced evaluation, real compilation/testing.
    """

    def __init__(
        self,
        judge_adapter: Optional[ModelAdapter] = None,
        sandbox: Optional[DockerSandbox] = None,
        enable_execution: bool = True,
    ):
        self.static_judge = StaticJudge()
        self.llm_judge = LLMJudge(judge_adapter) if judge_adapter else None
        self.sandbox = sandbox
        self.enable_execution = enable_execution and sandbox is not None

    async def evaluate(self, submission: Submission, domain: DomainConfig) -> Verdict:
        # Phase 1: Static regex checks (instant)
        static_verdict = await self.static_judge.evaluate(submission, domain)

        # If banned patterns hit → instant fail, skip LLM and execution
        if static_verdict.banned_hits:
            static_verdict.reasoning = (
                f"FAST-FAIL: Banned patterns detected: {static_verdict.banned_hits}. "
                f"Code rejected without further evaluation."
            )
            return static_verdict

        # Phase 2: Optional Docker execution (compile + test)
        compile_success = None
        test_success = None
        compile_output = ""
        test_output = ""

        if self.enable_execution and domain.compile_cmd:
            try:
                result = await self.sandbox.run_code(
                    submission.code,
                    domain.file_extension,
                    domain.compile_cmd,
                    domain.test_cmd,
                )
                compile_success = result.get("compile_success")
                test_success = result.get("test_success")
                compile_output = result.get("compile_output", "")[:2000]
                test_output = result.get("test_output", "")[:2000]
            except Exception as e:
                compile_output = f"Sandbox error: {e}"
                compile_success = False

        # Phase 3: LLM rubric evaluation (nuanced scoring)
        if self.llm_judge:
            llm_verdict = await self.llm_judge.evaluate(submission, domain)

            # Merge: combine static reward hits + LLM reasoning + execution results
            merged_score = llm_verdict.score

            # Adjust score based on compilation/test results
            if compile_success is False:
                merged_score = max(0.0, merged_score - 4.0)
                llm_verdict.reasoning += " | COMPILATION FAILED."
            elif compile_success is True:
                merged_score = min(10.0, merged_score + 1.0)
                llm_verdict.reasoning += " | Compilation passed."

            if test_success is True:
                merged_score = min(10.0, merged_score + 2.0)
                llm_verdict.reasoning += " | Tests passed."
            elif test_success is False:
                merged_score = max(0.0, merged_score - 3.0)
                llm_verdict.reasoning += " | Tests FAILED."

            return Verdict(
                submission_id=submission.id,
                task_id=submission.task_id,
                round=submission.round,
                score=round(merged_score, 2),
                passed=merged_score >= 7.0 and (compile_success is not False),
                reasoning=llm_verdict.reasoning,
                banned_hits=static_verdict.banned_hits,
                reward_hits=static_verdict.reward_hits,
                missing_patterns=llm_verdict.missing_patterns,
                compile_success=compile_success,
                test_success=test_success,
                compile_output=compile_output,
                test_output=test_output,
            )
        else:
            # No LLM judge available — return static verdict enhanced with execution
            if compile_success is False:
                static_verdict.score = max(0.0, static_verdict.score - 4.0)
                static_verdict.reasoning += " | COMPILATION FAILED."
            elif compile_success is True:
                static_verdict.score = min(10.0, static_verdict.score + 1.0)
                static_verdict.reasoning += " | Compilation passed."
            static_verdict.compile_success = compile_success
            static_verdict.test_success = test_success
            static_verdict.compile_output = compile_output
            static_verdict.test_output = test_output
            static_verdict.passed = static_verdict.score >= 7.0 and (compile_success is not False)
            return static_verdict


def make_judge(
    mode: JudgeMode,
    judge_adapter: Optional[ModelAdapter] = None,
    sandbox: Optional[DockerSandbox] = None,
    enable_execution: bool = True,
) -> BaseJudge:
    """Factory: create the appropriate judge based on mode."""
    if mode == JudgeMode.STATIC:
        return StaticJudge()
    elif mode == JudgeMode.LLM:
        if not judge_adapter:
            raise ValueError("LLM judge requires a model adapter")
        return LLMJudge(judge_adapter)
    else:  # HYBRID
        return HybridJudge(judge_adapter, sandbox, enable_execution)
PYEOF

# ─── domains/domain_base.py ───
cat > "$PROJECT_DIR/domains/domain_base.py" << 'PYEOF'
"""
Domain plugin system for EvoCoder.
Domains define banned/reward patterns, rubrics, compile/test commands, and output format.
"""
from __future__ import annotations

from typing import Optional
from core.schemas import DomainConfig


class DomainRegistry:
    """Registry for domain plugins. Supports built-in and runtime-registered domains."""

    _instance: Optional["DomainRegistry"] = None

    def __init__(self):
        self._domains: dict[str, DomainConfig] = {}
        self._register_builtin()

    @classmethod
    def get_instance(cls) -> "DomainRegistry":
        if cls._instance is None:
            cls._instance = DomainRegistry()
        return cls._instance

    def register(self, config: DomainConfig) -> None:
        self._domains[config.name] = config

    def get(self, name: str) -> Optional[DomainConfig]:
        return self._domains.get(name)

    def list_domains(self) -> list[str]:
        return sorted(self._domains.keys())

    def get_or_create(self, name: str, **overrides) -> DomainConfig:
        """
        Get a domain by name, or create a generic one with overrides.
        If the domain exists, apply overrides on top of it.
        """
        base = self._domains.get(name)
        if base is None:
            # Create a generic domain if not found
            base = DomainConfig(
                name=name,
                language=overrides.get("language", "unknown"),
                rubric=overrides.get("rubric", "Evaluate code quality, correctness, and completeness."),
                file_extension=overrides.get("file_extension", ".txt"),
            )
        # Apply overrides
        if overrides:
            for k, v in overrides.items():
                if hasattr(base, k) and v is not None:
                    setattr(base, k, v)
        return base

    def _register_builtin(self) -> None:
        """Register all built-in domains."""
        from domains.builtin_domains import register_all_builtin
        register_all_builtin(self)


def get_domain_registry() -> DomainRegistry:
    return DomainRegistry.get_instance()
PYEOF

# ─── domains/builtin_domains.py ───
cat > "$PROJECT_DIR/domains/builtin_domains.py" << 'PYEOF'
"""
Built-in domain configurations for EvoCoder.
Each domain defines banned/reward patterns, rubrics, and optional compile/test commands.
"""
from __future__ import annotations

from core.schemas import DomainConfig
from domains.domain_base import DomainRegistry


def register_all_builtin(registry: DomainRegistry) -> None:
    """Register all built-in domain plugins."""

    # ─── Generic (fallback for any task) ───
    registry.register(DomainConfig(
        name="generic",
        language="any",
        rubric=(
            "Evaluate code quality, correctness, best practices, and completeness. "
            "Code should be production-ready, well-structured, handle errors, and include "
            "appropriate comments. Penalize debug statements, TODO comments, and incomplete logic."
        ),
        file_extension=".txt",
        extra_context="The task is open-ended. Evaluate based on general software engineering quality.",
    ))

    # ─── Python ───
    registry.register(DomainConfig(
        name="python",
        language="python",
        banned_patterns=[
            r"\bprint\s*\(",           # debug print statements
            r"\bbreakpoint\s*\(",       # debugger calls
            r"\bpdb\.set_trace",        # pdb debugger
            r"\bos\.system\s*\(",       # shell injection risk
        ],
        reward_patterns=[
            r"\basync\s+def\b",        # async programming
            r"\bclass\s+\w+",          # class definitions
            r"\bdef\s+\w+",            # function definitions
            r"\btry\s*:",              # error handling
            r'""".*?"""',              # docstrings
            r"\bimport\s+\w+",         # proper imports
        ],
        rubric=(
            "Python code must: use proper type hints, handle exceptions explicitly, "
            "follow PEP 8 conventions, include docstrings for public functions, "
            "use async/await for I/O operations, and avoid global state. "
            "Penalize print() debugging, bare except clauses, and mutable default arguments."
        ),
        compile_cmd="python -m py_compile {file}",
        test_cmd="python -m pytest {file} -v --tb=short 2>&1 || true",
        file_extension=".py",
        extra_context="Write clean, production-ready Python code.",
    ))

    # ─── Rust ───
    registry.register(DomainConfig(
        name="rust",
        language="rust",
        banned_patterns=[
            r"\bprintln!\s*\(",        # debug printing (use logging instead)
            r"\bunwrap\s*\(\s*\)",     # unwrap() panics
            r"\beprintln!\s*\(",       # debug stderr
            r"\bthread::sleep",        # blocking sleeps without reason
        ],
        reward_patterns=[
            r"\basync\s+fn\b",        # async functions
            r"#\[tokio::main\]",       # tokio runtime
            r"#\[test\]",              # unit tests
            r"\bResult<",              # proper error handling
            r"\bthiserror|#\[derive\(.*Error", # error types
            r"impl\s+\w+",            # implementations
        ],
        rubric=(
            "Rust code must: use Result/Option instead of unwrap(), implement proper error types "
            "with thiserror or anyhow, use async/await with tokio for I/O, include unit tests with #[test], "
            "and follow clippy conventions. Penalize unwrap(), println! debugging, and unsafe blocks."
        ),
        file_extension=".rs",
        extra_context="Write idiomatic, safe Rust code.",
    ))

    # ─── Web (HTML/JS/CSS) ───
    registry.register(DomainConfig(
        name="web",
        language="html",
        banned_patterns=[
            r"\balert\s*\(",          # alert debugging
            r"\bconsole\.log\s*\(",   # console debugging
            r"\bdocument\.write\s*\(",# deprecated DOM manipulation
            r"<script\s+src=.*http://", # insecure external scripts (use https)
        ],
        reward_patterns=[
            r"\basync\s+function\b|\basync\s+\(", # async JS
            r"\bfetch\s*\(",          # fetch API
            r"<!DOCTYPE html>",       # proper HTML5 doctype
            r'lang="',                # accessibility: lang attribute
            r"aria-\w+",             # accessibility attributes
            r"@media",               # responsive design
        ],
        rubric=(
            "Web code must: use modern ES6+ JavaScript, follow accessibility (WCAG) guidelines, "
            "use async/await with fetch, include responsive design with @media queries, "
            "and avoid inline event handlers. Penalize console.log debugging, alert(), and document.write()."
        ),
        file_extension=".html",
        extra_context="Write modern, accessible, responsive web code.",
    ))

    # ─── Android SAF (ported from AI Coding Arena) ───
    registry.register(DomainConfig(
        name="android_saf",
        language="java",
        banned_patterns=[
            r"\bjava\.io\.File\b",
            r"getExternalStorageDirectory",
            r"getParentFile\s*\(\s*\)",
            r"Uri\.fromFile",
            r"getExternalFilesDir",
            r"Environment\.getExternal",
        ],
        reward_patterns=[
            r"ACTION_OPEN_DOCUMENT_TREE",
            r"takePersistableUriPermission",
            r"DocumentFile\.fromTreeUri",
            r"DocumentsContract",
            r"ActivityResultLauncher",
        ],
        rubric=(
            "Android code must: use Storage Access Framework (SAF) exclusively, "
            "use ACTION_OPEN_DOCUMENT_TREE for folder selection, persist URI permissions with "
            "takePersistableUriPermission(), use DocumentFile for CRUD operations, and target "
            "Android 14 (SDK 34). Penalize any use of java.io.File, getExternalStorageDirectory(), "
            "or legacy storage APIs."
        ),
        file_extension=".java",
        extra_context="Write Android 14 code using Storage Access Framework only. No legacy File APIs.",
    ))

    # ─── C++ ───
    registry.register(DomainConfig(
        name="cpp",
        language="cpp",
        banned_patterns=[
            r"\bnew\s+\w+\s*\[",     # manual array allocation (use vectors)
            r"\bdelete\s+\w+\s*\[",  # manual deallocation
            r"\bprintf\s*\(",        # C-style printing
            r"\bmalloc\s*\(",        # C-style allocation
            r"\bfree\s*\(",         # C-style deallocation
        ],
        reward_patterns=[
            r"\bconstexpr\b",        # compile-time constants
            r"\braii\b|std::unique_ptr|std::shared_ptr", # RAII
            r"\bauto\s+&",           # modern auto references
            r"#include\s+<memory>",  # smart pointers
            r"std::vector",          # vectors over arrays
            r"#include\s+<thread>",  # threading
        ],
        rubric=(
            "C++ code must: use RAII and smart pointers (unique_ptr, shared_ptr), prefer std::vector over raw arrays, "
            "use constexpr for compile-time computations, use std::thread or async for concurrency, "
            "and avoid manual new/delete. Penalize printf(), malloc/free, raw pointers, and C-style casts."
        ),
        file_extension=".cpp",
        extra_context="Write modern C++17/20 code with RAII and smart pointers.",
    ))

    # ─── Dockerfile ───
    registry.register(DomainConfig(
        name="dockerfile",
        language="dockerfile",
        banned_patterns=[
            r"FROM\s+\w+:\latest",   # avoid :latest tag
            r"\bapt-get install.*without.*--no-install-recommends", # bloated layers
            r"chmod\s+777",          # security: no 777
        ],
        reward_patterns=[
            r"FROM\s+\w+:\d+\.\d+",  # pinned version tags
            r"USER\s+\w+",          # non-root user
            r"HEALTHCHECK",          # health checks
            r"--no-install-recommends", # slim installs
            r"COPY\s+--from=",      # multi-stage builds
        ],
        rubric=(
            "Dockerfile must: use pinned version tags (not :latest), run as non-root user, "
            "include HEALTHCHECK, use multi-stage builds for size optimization, and use "
            "--no-install-recommends for apt-get. Penalize :latest tags, chmod 777, and bloated layers."
        ),
        file_extension=".dockerfile",
        extra_context="Write production-ready Dockerfiles with security best practices.",
    ))

    # ─── Shell / Bash ───
    registry.register(DomainConfig(
        name="shell",
        language="bash",
        banned_patterns=[
            r"\brm\s+-rf\s+/",      # dangerous rm
            r"\beval\s+",            # eval injection risk
            r"\bchmod\s+777",        # security
            r"\bcurl\s+.*\|\s*sh",   # curl pipe to shell
        ],
        reward_patterns=[
            r"set\s+-euo\s+pipefail|set\s+-eu", # safe shell
            r"\btrap\s+",            # cleanup traps
            r"\b\[",                 # test brackets over [[
            r"\bgetopts",            # argument parsing
            r"\bfunction\s+\w+",    # named functions
        ],
        rubric=(
            "Shell scripts must: use set -euo pipefail, implement cleanup traps, use proper argument "
            "parsing with getopts, define functions, and quote all variables. Penalize rm -rf /, "
            "eval, curl pipe to sh, and unquoted variables."
        ),
        file_extension=".sh",
        extra_context="Write safe, production-ready shell scripts.",
    ))
PYEOF

# ─── prompts/templates.py ───
cat > "$PROJECT_DIR/prompts/templates.py" << 'PYEOF'
"""
Jinja2-based prompt templates for EvoCoder.
Generates task prompts, judge prompts, and meta-agent prompts dynamically.
"""
from __future__ import annotations

from jinja2 import Template
from typing import Optional
from core.schemas import DomainConfig, Verdict, Submission


# ─── System Prompts ───

TASK_AGENT_SYSTEM = Template("""You are an expert {{ domain.language }} developer participating in a competitive coding arena.

Domain: {{ domain.name }}
Language: {{ domain.language }}
{{ domain.extra_context }}

Rules:
1. Output ONLY code in a single fenced code block. No explanations, no bullet lists, no release notes.
2. If you receive feedback from a previous round, address ALL issues mentioned.
3. Do not reintroduce patterns that were previously flagged as banned.
4. Your code must be complete and production-ready.
5. Language: {{ domain.language }}

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


# ─── Task User Prompt ───

TASK_AGENT_USER = Template("""## Task
{{ task_description }}

{% if previous_code %}
## Your Previous Submission (Round {{ round - 1 }})
