
Evaluate this code. Return JSON only.""")


# ─── Meta-Agent Prompts ───

META_AGENT_SYSTEM = Template("""You are a meta-agent whose job is to improve the evaluation and prompt system of a competitive coding arena.

You analyze performance data from previous rounds and propose changes to:
1. Judge rules (banned/reward patterns, rubric text)
2. Prompt templates (system prompt, task framing)

Your changes must be specific and justified by performance data. Output a JSON object:
{
  "target": "domain_config" | "prompts",
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
Analyze the performance data. Are the judge rules catching real issues? Are they missing anything?
Propose changes to improve the evaluation quality. The goal is better discrimination between
high-quality and low-quality code.

Return JSON only.""")


# ─── Code Extraction ───

def extract_code_block(text: str) -> str:
    """Extract the first fenced code block from LLM output. Falls back to raw text."""
    import re
    # Match ```lang\n...\n``` or ```\n...\n```
    matches = re.findall(r'```(?:\w+)?\n(.*?)```', text, re.DOTALL)
    if matches:
        return matches[0].strip()
    # No code block found — return raw text (may be pure code without fences)
    return text.strip()


# ─── Verdict Feedback Formatter ───

def format_verdict_feedback(verdict: Verdict) -> str:
    """Format a verdict into concise feedback for the next round's prompt."""
    parts = [f"Score: {verdict.score}/10"]
    
    if verdict.banned_hits:
        parts.append(f"BANNED patterns hit: {', '.join(verdict.banned_hits)}")
    if verdict.missing_patterns:
        parts.append(f"Missing/required patterns: {', '.join(verdict.missing_patterns)}")
    if verdict.reward_hits:
        parts.append(f"Good patterns found: {', '.join(verdict.reward_hits)}")
    if verdict.compile_success is False:
        parts.append(f"COMPILATION FAILED: {verdict.compile_output[:200]}")
    elif verdict.compile_success is True:
        parts.append("Compilation passed.")
    if verdict.test_success is False:
        parts.append(f"TESTS FAILED: {verdict.test_output[:200]}")
    elif verdict.test_success is True:
        parts.append("Tests passed.")
    if verdict.reasoning:
        parts.append(f"Judge reasoning: {verdict.reasoning}")
    
    return "\n".join(parts)


# ─── Render Functions ───

def render_task_prompt(
    domain: DomainConfig,
    task_description: str,
    round: int,
    previous_code: Optional[str] = None,
    verdict_feedback: Optional[str] = None,
    opponent_code: Optional[str] = None,
    opponent_score: Optional[float] = None,
    parent_code: Optional[str] = None,
    generation: int = 0,
    dueling: bool = False,
) -> tuple[str, str]:
    """Render (system_prompt, user_prompt) for a task agent."""
    system = TASK_AGENT_SYSTEM.render(domain=domain)
    user = TASK_AGENT_USER.render(
        domain=domain,
        task_description=task_description,
        round=round,
        previous_code=previous_code,
        verdict_feedback=verdict_feedback,
        opponent_code=opponent_code if dueling else None,
        opponent_score=opponent_score if dueling else None,
        parent_code=parent_code,
        generation=generation,
        dueling=dueling,
    )
    return system.strip(), user.strip()


def render_judge_prompt(domain: DomainConfig, code: str) -> tuple[str, str]:
    """Render (system_prompt, user_prompt) for the LLM judge."""
    system = JUDGE_SYSTEM.render(domain=domain)
    user = JUDGE_USER.render(domain=domain, code=code)
    return system.strip(), user.strip()


def render_meta_prompt(
    domain: DomainConfig,
    rounds_data: list[dict],
    avg_first_half: float,
    avg_second_half: float,
) -> tuple[str, str]:
    """Render (system_prompt, user_prompt) for the meta-agent."""
    half = len(rounds_data) // 2 if rounds_data else 0
    system = META_AGENT_SYSTEM.render()
    user = META_AGENT_USER.render(
        domain=domain,
        rounds=rounds_data,
        half=half,
        avg_first_half=avg_first_half,
        avg_second_half=avg_second_half,
    )
    return system.strip(), user.strip()
PYEOF

# ─── sandbox/sandbox.py ───
cat > "$PROJECT_DIR/sandbox/sandbox.py" << 'PYEOF'
"""
Docker-based sandbox for safe code execution.
Compiles and tests model-generated code in isolated containers.
"""
from __future__ import annotations

import asyncio
import tempfile
import os
from pathlib import Path
from typing import Optional
import json

try:
    import aiodocker
    HAS_AIODOCKER = True
except ImportError:
    HAS_AIODOCKER = False

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
    Executes code in a Docker container for compilation and testing.
    Falls back gracefully if Docker is not available.
    """

    def __init__(
        self,
        image: str = SANDBOX_IMAGE,
        timeout: int = TIMEOUT_SECONDS,
        max_output: int = MAX_OUTPUT,
        memory_limit: str = "512m",
        cpu_limit: int = 1,
    ):
        self.image = image
        self.timeout = timeout
        self.max_output = max_output
        self.memory_limit = memory_limit
        self.cpu_limit = cpu_limit
        self._available = self._check_docker()

    def _check_docker(self) -> bool:
        """Check if Docker is available."""
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

    async def run_code(
        self,
        code: str,
        file_extension: str,
        compile_cmd: Optional[str] = None,
        test_cmd: Optional[str] = None,
    ) -> dict:
        """
        Run code in a sandboxed Docker container.
        Returns dict with compile_success, test_success, compile_output, test_output.
        """
        if not self._available:
            return {
                "compile_success": None,
                "test_success": None,
                "compile_output": "Docker not available — execution skipped.",
                "test_output": "",
            }

        # Write code to a temp directory
        with tempfile.TemporaryDirectory() as tmpdir:
            filename = f"submission{file_extension}"
            filepath = os.path.join(tmpdir, filename)
            with open(filepath, "w") as f:
                f.write(code)

            compile_output = ""
            test_output = ""
            compile_success = None
            test_success = None

            # Run compile command
            if compile_cmd:
                cmd = compile_cmd.replace("{file}", f"/workspace/{filename}")
                try:
                    result = await self._exec_in_container(cmd, tmpdir)
                    compile_output = result["output"][: self.max_output]
                    compile_success = result["exit_code"] == 0
                except asyncio.TimeoutError:
                    compile_output = f"Compilation timed out after {self.timeout}s"
                    compile_success = False
                except Exception as e:
                    compile_output = f"Compilation error: {e}"
                    compile_success = False

            # Run test command (only if compilation succeeded)
            if test_cmd and compile_success is not False:
                cmd = test_cmd.replace("{file}", f"/workspace/{filename}")
                try:
                    result = await self._exec_in_container(cmd, tmpdir)
                    test_output = result["output"][: self.max_output]
                    test_success = result["exit_code"] == 0
                except asyncio.TimeoutError:
                    test_output = f"Tests timed out after {self.timeout}s"
                    test_success = False
                except Exception as e:
                    test_output = f"Test error: {e}"
                    test_success = False

            return {
                "compile_success": compile_success,
                "test_success": test_success,
                "compile_output": compile_output,
                "test_output": test_output,
            }

    async def _exec_in_container(self, cmd: str, mount_dir: str) -> dict:
        """Execute a command in a Docker container with the mount dir."""
        if not HAS_DOCKER:
            raise RuntimeError("Docker SDK not installed")

        # Use synchronous docker in a thread pool to avoid blocking
        loop = asyncio.get_event_loop()

        def _run():
            client = docker_sync.from_env()
            try:
                container = client.containers.run(
                    self.image,
                    command=["sh", "-c", cmd],
                    volumes={
                        os.path.abspath(mount_dir): {"bind": "/workspace", "mode": "ro"}
                    },
                    working_dir="/workspace",
                    mem_limit=self.memory_limit,
                    cpu_quota=int(self.cpu_limit * 100000),
                    network_mode="none",  # no network access
                    detach=True,
                    stderr=True,
                    stdout=True,
                )
                try:
                    result = container.wait(timeout=self.timeout)
                    logs = container.logs().decode("utf-8", errors="replace")
                    exit_code = result.get("StatusCode", -1)
                    return {"output": logs, "exit_code": exit_code}
                finally:
                    container.remove(force=True)
            except Exception as e:
                return {"output": str(e), "exit_code": -1}
            finally:
                client.close()

        return await loop.run_in_executor(None, _run)


class NullSandbox:
    """No-op sandbox for when Docker isn't available. Returns None for all results."""

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


def get_sandbox(enabled: bool = True) -> "DockerSandbox | NullSandbox":
    """Get a Docker sandbox if available and enabled, otherwise a null sandbox."""
    if not enabled:
        return NullSandbox()
    sandbox = DockerSandbox()
    if sandbox.available:
        return sandbox
    return NullSandbox()
PYEOF

# ─── core/controller.py ───
cat > "$PROJECT_DIR/core/controller.py" << 'PYEOF'
"""
Controller engine for EvoCoder.
Orchestrates rounds, dispatches models, invokes judges, tracks lineage, selects parents.
This is the heart of the evolutionary system.
"""
from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
from pathlib import Path
from typing import Optional, AsyncIterator, Callable

from core.schemas import (
    BattleConfig, Task, Submission, Verdict, Lineage, Side, JudgeMode, DomainConfig
)
from core.persistence import (
    init_db, get_db, save_task, save_submission, save_verdict, save_lineage,
    get_continuation_context, get_winning_submission, get_last_round,
    get_submissions_for_round, get_verdicts_for_round, update_leaderboard,
    get_latest_verdicts,
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

    def __init__(self, config: BattleConfig, db_path: Path = Path("evocoder.db")):
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
            judge_mode=config.judge_mode,
            rules_override=config.rules_override,
        )
        save_task(self.conn, self.task)

        # Track current state
        self.current_round = 0
        self.parent_submission: Optional[Submission] = None  # winner of previous round
        self.parent_verdict: Optional[Verdict] = None
        self._running = False

        # Callback for streaming output
        self.on_event: Optional[Callable] = None

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

            # Handle exceptions
            submissions = []
            for i, result in enumerate(results):
                side = Side.A if i == 0 else Side.B
                if isinstance(result, Exception):
                    logger.error(f"Side {side} generation failed: {result}")
                    yield {"type": "error", "side": side.value, "error": str(result)}
                    # Create a minimal failed submission
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
                    logger.error(f"Judge failed for side {side}: {v}")
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

            # Select winner
            v_a, v_b = verdicts[0], verdicts[1] if not isinstance(verdicts[1], Exception) else Verdict(
                submission_id=submissions[1].id, task_id=self.task.id, round=round_num, score=0.0, passed=False, reasoning="Judge failed"
            )
            if not isinstance(v_a, Verdict): v_a = Verdict(submission_id=submissions[0].id, task_id=self.task.id, round=round_num, score=0.0, passed=False, reasoning="Judge failed")
            if not isinstance(v_b, Verdict): v_b = Verdict(submission_id=submissions[1].id, task_id=self.task.id, round=round_num, score=0.0, passed=False, reasoning="Judge failed")

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
            if winner_verdict.score >= 10.0 and winner_verdict.banned_hits == []:
                if winner_verdict.compile_success is not False and winner_verdict.test_success is not False:
                    yield {"type": "stability_reached", "round": round_num, "score": 10.0}
                    break

        # Extract final winning code
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
        self.conn.close()

    def stop(self):
        self._running = False

    async def _generate_side(self, side: Side, round_num: int) -> Submission:
        """Generate code for one side in a round."""
        adapter = self.side_a if side == Side.A else self.side_b
        model_name = self.config.side_a_model if side == Side.A else self.config.side_b_model

        # Get previous feedback for this side
        prev_verdict = None
        if round_num > 1:
            prev_submissions = get_submissions_for_round(self.conn, self.task.id, round_num - 1)
            prev_verdicts = get_verdicts_for_round(self.conn, self.task.id, round_num - 1)
            # Find this side's verdict
            for v in prev_verdicts:
                # Match by submission's side
                for s in prev_submissions:
                    if v.submission_id == s.id and s.side == side:
                        prev_verdict = v
                        break

        prev_code = None
        verdict_feedback = None
        if prev_verdict:
            # Find the previous code from this side
            prev_submissions = get_submissions_for_round(self.conn, self.task.id, round_num - 1)
            for s in prev_submissions:
                if s.side == side:
                    prev_code = s.code
                    break
            verdict_feedback = format_verdict_feedback(prev_verdict)

        # Get opponent's code (for dueling mode)
        opponent_code = None
        opponent_score = None
        if round_num > 1:
            prev_submissions = get_submissions_for_round(self.conn, self.task.id, round_num - 1)
            prev_verdicts_list = get_verdicts_for_round(self.conn, self.task.id, round_num - 1)
            for s in prev_submissions:
                if s.side != side:
                    opponent_code = s.code
                    for v in prev_verdicts_list:
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
PYEOF

# ─── core/meta_agent.py ───
cat > "$PROJECT_DIR/core/meta_agent.py" << 'PYEOF'
"""
Meta-agent for EvoCoder — the self-referential improvement loop.

The meta-agent reviews performance data from completed rounds and proposes
changes to the domain configuration (banned/reward patterns, rubric text).
Changes are evaluated by comparing fitness before and after application.
Promoted changes become the new baseline; reverted changes are archived.

This is what makes the system truly evolutionary rather than just iterative:
the selection pressure (judge rules) itself evolves over time.
"""
from __future__ import annotations

import json
import logging
import sqlite3
from typing import Optional
from dataclasses import asdict

from core.schemas import MetaChange, DomainConfig, Side
from core.persistence import (
    save_meta_change, update_meta_change, get_meta_changes,
    get_submissions_for_round, get_verdicts_for_round, get_verdicts_for_round,
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
    4. Run a few rounds with the new config.
    5. Compare average fitness before vs. after.
    6. If improved → promote (keep changes). If not → revert.
    7. Store the MetaChange record for audit trail.
    """

    def __init__(self, adapter: ModelAdapter, conn: sqlite3.Connection):
        self.adapter = adapter
        self.conn = conn

    async def propose_changes(
        self,
        domain: DomainConfig,
        task_id: str,
        current_round: int,
    ) -> Optional[MetaChange]:
        """
        Analyze recent rounds and propose changes to domain config.
        Returns a MetaChange if the agent proposes something, None otherwise.
        """
        # Gather round data
        rounds_data = self._collect_round_data(task_id, current_round)
        if len(rounds_data) < 2:
            logger.info("Meta-agent: not enough rounds to analyze yet (have %d)", len(rounds_data))
            return None

        # Calculate fitness trend
        half = len(rounds_data) // 2 or 1
        first_half_scores = [r["side_a_score"] + r["side_b_score"] for r in rounds_data[:half] if r["side_a_score"] is not None and r["side_b_score"] is not None]
        second_half_scores = [r["side_a_score"] + r["side_b_score"] for r in rounds_data[half:] if r["side_a_score"] is not None and r["side_b_score"] is not None]
        avg_first = sum(first_half_scores) / len(first_half_scores) if first_half_scores else 0.0
        avg_second = sum(second_half_scores) / len(second_half_scores) if second_half_scores else 0.0

        # Render prompt
        system, user = render_meta_prompt(domain, rounds_data, avg_first, avg_second)

        try:
            response = await self.adapter.complete(system, user, temperature=0.2)
            # Parse JSON from response
            response = response.strip()
            if response.startswith("```"):
                lines = response.split("\n")
                response = "\n".join(lines[1:-1]) if lines[-1].startswith("```") else "\n".join(lines[1:])

            result = json.loads(response)
            changes = result.get("changes", [])
            if not changes:
                logger.info("Meta-agent: no changes proposed")
                return None

            # Build patch string for storage
            patch = json.dumps(changes, indent=2)
            summary = result.get("summary", "No summary provided")

            mc = MetaChange(
                task_id=task_id,
                round=current_round,
                target_file="domain_config",
                patch=patch,
                reasoning=summary,
                fitness_before=avg_second,  # current fitness level
            )
            save_meta_change(self.conn, mc)
            logger.info("Meta-agent proposed %d changes: %s", len(changes), summary)
            return mc

        except (json.JSONDecodeError, KeyError, ValueError) as e:
            logger.error("Meta-agent response parse error: %s", e)
            return None

    def apply_changes(self, domain: DomainConfig, mc: MetaChange) -> DomainConfig:
        """
        Apply proposed changes to the domain config.
        Returns a new DomainConfig with the changes applied (does not mutate the original).
        """
        import copy
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

            logger.info("Applied change: %s %s on %s — %s", action, field, value[:50], reasoning)

        update_meta_change(self.conn, mc.id, applied=1)
        return new_domain

    def evaluate_fitness_delta(self, mc: MetaChange, post_fitness: float) -> bool:
        """
        Compare fitness before and after the change.
        Returns True if the change should be promoted (kept).
        """
        mc.fitness_after = post_fitness
        delta = post_fitness - mc.fitness_before

        # Promote if fitness improved by at least 0.5 points
        # (smaller threshold to allow minor refinements)
        should_promote = delta >= 0.5

        update_meta_change(
            self.conn, mc.id,
            promoted=1 if should_promote else 0,
            fitness_after=post_fitness,
        )

        if should_promote:
            logger.info(
                "Meta-change PROMOTED: fitness %.2f → %.2f (Δ%.2f)",
                mc.fitness_before, post_fitness, delta
            )
        else:
            logger.info(
                "Meta-change REVERTED: fitness %.2f → %.2f (Δ%.2f)",
                mc.fitness_before, post_fitness, delta
            )

        return should_promote

    def _collect_round_data(self, task_id: str, current_round: int, lookback: int = 6) -> list[dict]:
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
            side_a_verdict = next((v for v in verdicts if v.submission_id == (side_a_sub.id if side_a_sub else "")), None)
            side_b_verdict = next((v for v in verdicts if v.submission_id == (side_b_sub.id if side_b_sub else "")), None)

            winner = "A" if side_a_verdict and side_b_verdict and side_a_verdict.score >= side_b_verdict.score else "B"

            rounds_data.append({
                "round": r,
                "side_a_model": side_a_sub.model if side_a_sub else "unknown",
                "side_a_score": side_a_verdict.score if side_a_verdict else None,
                "side_a_issues": ", ".join(side_a_verdict.missing_patterns) if side_a_verdict else "",
                "side_b_model": side_b_sub.model if side_b_sub else "unknown",
                "side_b_score": side_b_verdict.score if side_b_verdict else None,
                "side_b_issues": ", ".join(side_b_verdict.missing_patterns) if side_b_verdict else "",
                "winner": winner,
            })

        return rounds_data
PYEOF

# ─── main.py ───
cat > "$PROJECT_DIR/main.py" << 'PYEOF'
"""
FastAPI + WebSocket server for EvoCoder.
Entry point for the autonomous evolutionary coding engine.
"""
from __future__ import annotations

import asyncio
import json
import os
import logging
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from core.schemas import BattleConfig, JudgeMode
from core.controller import BattleController
from core.meta_agent import MetaAgent
from core.persistence import (
    init_db, get_db, get_leaderboard, get_continuation_context,
    get_meta_changes, get_lineage_tree,
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
    api_base: str = Field("http://localhost:11434/v1", description="OpenAI-compatible API base URL")
    api_key: str = Field("")


class RegisterTopicRequest(BaseModel):
    topic: str


# ─── App setup ───

app = FastAPI(title="EvoCoder", description="Autonomous Evolutionary Coding Engine")

STATIC_DIR = Path(__file__).parent / "static"
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

# Topic cache for large topics (avoids URL length issues with WebSocket)
TOPIC_CACHE: dict[str, str] = {}


# ─── REST Endpoints ───

@app.get("/", response_class=HTMLResponse)
async def index():
    """Serve the web UI."""
    index_file = STATIC_DIR / "index.html"
    if index_file.exists():
        return HTMLResponse(index_file.read_text())
    return HTMLResponse("<h1>EvoCoder</h1><p>Web UI not found. Place index.html in static/</p>")


@app.get("/api/domains")
async def list_domains():
    """List all available domain plugins."""
    registry = get_domain_registry()
    domains = []
    for name in registry.list_domains():
        domain = registry.get(name)
        if domain:
            domains.append({
                "name": name,
                "language": domain.language,
                "has_banned_rules": bool(domain.banned_patterns),
                "has_reward_rules": bool(domain.reward_patterns),
                "has_compile_cmd": bool(domain.compile_cmd),
                "has_test_cmd": bool(domain.test_cmd),
                "file_extension": domain.file_extension,
            })
    return {"domains": domains}


@app.get("/api/leaderboard")
async def leaderboard():
    """Get the model leaderboard."""
    conn = get_db()
    board = get_leaderboard(conn)
    conn.close()
    return {"leaderboard": board}


@app.get("/api/continuation")
async def continuation(task_id: str, limit: int = 1):
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
    return {"status": "ok", "version": "1.0.0"}


# ─── WebSocket: Live Battle Stream ───

@app.websocket("/ws/battle")
async def ws_battle(websocket: WebSocket):
    """
    WebSocket endpoint for live battle streaming.
    Client sends a BattleRequest as JSON. Server streams events back.
    """
    await websocket.accept()
    controller = None
    try:
        # Receive battle config
        raw = await websocket.receive_text()
        data = json.loads(raw)

        # Check for topic token
        if "token" in data and data["token"] in TOPIC_CACHE:
            data["task_description"] = TOPIC_CACHE.pop(data["token"])

        # Build battle config
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

        # Run battle
        controller = BattleController(config)
        if config.enable_meta and config.meta_model:
            # Meta-agent enabled: interleave meta-analysis between rounds
            from models.model_adapters import make_adapter as _make_adapter
            meta_adapter = _make_adapter(config.meta_model, config.api_base, config.api_key)
            meta = MetaAgent(meta_adapter, controller.conn)

            async for event in controller.run():
                await websocket.send_text(json.dumps(event, default=str))

                # Run meta-agent at intervals
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
                        # Calculate post-change fitness (use next few rounds' average)
                        # For now, estimate from current trajectory
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
        logger.error(f"WebSocket error: {e}", exc_info=True)
        await websocket.send_text(json.dumps({"type": "error", "message": str(e)}))
    finally:
        if controller and hasattr(controller, "conn"):
            try:
                controller.conn.close()
            except Exception:
                pass


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
PYEOF

# ─── static/index.html ───
cat > "$PROJECT_DIR/static/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EvoCoder — Autonomous Evolutionary Coding Engine</title>
    <style>
        :root {
            --bg: #0d1117;
            --surface: #161b22;
            --border: #30363d;
            --text: #e6edf3;
            --text-dim: #8b949e;
            --accent: #58a6ff;
            --accent-dim: #1f6feb;
            --success: #3fb950;
            --danger: #f85149;
            --warning: #d29922;
            --side-a: #58a6ff;
            --side-b: #bc8cff;
            --meta: #d29922;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', monospace;
            background: var(--bg);
            color: var(--text);
            font-size: 14px;
            line-height: 1.6;
        }
        .header {
            padding: 16px 24px;
            border-bottom: 1px solid var(--border);
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .header h1 { font-size: 20px; }
        .header .tag {
            font-size: 11px;
            padding: 2px 8px;
            border-radius: 4px;
            background: var(--accent-dim);
            color: var(--text);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .container {
            display: grid;
            grid-template-columns: 320px 1fr 320px;
            gap: 1px;
            height: calc(100vh - 57px);
        }
        .panel {
            background: var(--surface);
            overflow-y: auto;
            padding: 16px;
        }
        .panel-title {
            font-size: 12px;
            text-transform: uppercase;
            color: var(--text-dim);
            letter-spacing: 1px;
            margin-bottom: 12px;
            border-bottom: 1px solid var(--border);
            padding-bottom: 8px;
        }
        .form-group { margin-bottom: 12px; }
        .form-group label {
            display: block;
            font-size: 12px;
            color: var(--text-dim);
            margin-bottom: 4px;
        }
        .form-group input, .form-group select, .form-group textarea {
            width: 100%;
            padding: 8px 10px;
            background: var(--bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            color: var(--text);
            font-size: 13px;
            font-family: inherit;
        }
        .form-group textarea { resize: vertical; min-height: 80px; }
        .form-group input:focus, .form-group select:focus, .form-group textarea:focus {
            outline: none;
            border-color: var(--accent);
        }
        .model-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
        .toggle {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 12px;
        }
        .toggle input[type="checkbox"] {
            width: 16px; height: 16px;
            accent-color: var(--accent);
        }
        .toggle label { font-size: 12px; color: var(--text-dim); }
        .btn-primary {
            width: 100%;
            padding: 12px;
            background: var(--accent-dim);
            color: var(--text);
            border: none;
            border-radius: 6px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.2s;
        }
        .btn-primary:hover { background: var(--accent); }
        .btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
        .btn-secondary {
            width: 100%;
            padding: 8px;
            background: transparent;
            color: var(--text-dim);
            border: 1px solid var(--border);
            border-radius: 6px;
            font-size: 12px;
            cursor: pointer;
            margin-top: 8px;
        }
        .btn-secondary:hover { border-color: var(--accent); }
        .round-header {
            font-size: 14px;
            font-weight: 600;
            color: var(--text-dim);
            padding: 8px 0;
            border-bottom: 1px solid var(--border);
        }
        .round-header span { color: var(--accent); }
        .card {
            background: var(--bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 12px;
        }
        .card.a-side { border-top: 3px solid var(--side-a); }
        .card.b-side { border-top: 3px solid var(--side-b); }
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
        }
        .card-title { font-size: 13px; font-weight: 600; }
        .card-score {
            font-size: 18px;
            font-weight: 700;
            padding: 2px 10px;
            border-radius: 4px;
        }
        .card-score.high { color: var(--success); }
        .card-score.mid { color: var(--warning); }
        .card-score.low { color: var(--danger); }
        .card-model { font-size: 11px; color: var(--text-dim); margin-bottom: 8px; }
        .card-verdict { font-size: 12px; color: var(--text-dim); }
        .card-banned { color: var(--danger); font-weight: 600; }
        .card-code {
            margin-top: 8px;
            background: var(--surface);
            border-radius: 6px;
            padding: 10px;
            font-family: 'Fira Code', 'Monaco', monospace;
            font-size: 11px;
            max-height: 300px;
            overflow-y: auto;
            white-space: pre-wrap;
            color: var(--text-dim);
        }
        .meta-banner {
            background: rgba(210, 153, 34, 0.1);
            border: 1px solid var(--meta);
            border-radius: 6px;
            padding: 10px;
            font-size: 12px;
            color: var(--meta);
        }
        .meta-banner .promoted { color: var(--success); }
        .meta-banner .reverted { color: var(--danger); }
        .status-bar {
            padding: 8px 12px;
            background: var(--surface);
            border-radius: 6px;
            font-size: 12px;
            color: var(--text-dim);
        }
        .sidebar-section { margin-bottom: 20px; }
        .leaderboard-item {
            display: flex;
            justify-content: space-between;
            padding: 6px 0;
            border-bottom: 1px solid var(--border);
            font-size: 12px;
        }
        .leaderboard-item .model { color: var(--text); }
        .leaderboard-item .elo { color: var(--accent); font-weight: 600; }
        .lineage-item {
            font-size: 11px;
            padding: 4px 0;
            border-bottom: 1px solid var(--border);
        }
        .lineage-item .gen { color: var(--text-dim); }
        .lineage-item .winner { color: var(--success); }
        .spinner {
            display: inline-block;
            width: 14px; height: 14px;
            border: 2px solid var(--border);
            border-top-color: var(--accent);
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        .loading { display: flex; align-items: center; gap: 8px; color: var(--text-dim); font-size: 12px; }
    </style>
</head>
<body>

<div class="header">
    <h1>🧬 EvoCoder</h1>
    <span class="tag">Autonomous Evolutionary Coding Engine</span>
</div>

<div class="container">
    <div class="panel" id="config-panel">
        <div class="panel-title">Battle Configuration</div>
        <div class="form-group">
            <label>Task Description</label>
            <textarea id="task-description" placeholder="Write a Python async web scraper with retry logic and error handling..."></textarea>
        </div>
        <div class="form-group">
            <label>Domain</label>
            <select id="domain-select">
                <option value="generic">Generic (auto-detect)</option>
            </select>
        </div>
        <div class="form-group">
            <label>Side A Model (Implementer)</label>
            <input type="text" id="side-a-model" value="qwen2-coder:14b" placeholder="model name">
        </div>
        <div class="form-group">
            <label>Side B Model (Challenger)</label>
            <input type="text" id="side-b-model" value="mistral:8x7b-instruct" placeholder="model name">
        </div>
        <div class="form-group">
            <label>Judge Model</label>
            <input type="text" id="judge-model" value="qwen3-coder:30b" placeholder="model name">
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
            <label>Enable Meta-Agent (self-referential improvement)</label>
        </div>
        <div class="form-group" id="meta-model-group" style="display:none;">
            <label>Meta-Agent Model</label>
            <input type="text" id="meta-model" value="qwen3-coder:30b" placeholder="model name">
        </div>
        <div class="form-group">
            <label>API Base URL</label>
            <input type="text" id="api-base" value="http://localhost:11434/v1" placeholder="OpenAI-compatible endpoint">
        </div>
        <div class="form-group">
            <label>API Key (optional)</label>
            <input type="password" id="api-key" placeholder="leave empty for local models">
        </div>
        <button class="btn-primary" id="start-btn" onclick="startBattle()">START BATTLE</button>
        <button class="btn-secondary" onclick="loadLeaderboard()">Refresh Leaderboard</button>
        <button class="btn-secondary" onclick="loadDomains()">Load Domains</button>
    </div>
    <div class="panel" id="arena-panel">
        <div class="panel-title">Live Arena</div>
        <div id="arena-content">
            <div class="status-bar">Configure a battle and press START to begin evolution.</div>
        </div>
    </div>
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
                <div style="color: var(--text-dim); font-size: 12px;">No lineage data yet.</div>
            </div>
        </div>
        <div class="sidebar-section">
            <div class="panel-title">Meta-Agent Log</div>
            <div id="meta-log">
                <div style="color: var(--text-dim); font-size: 12px;">Meta-agent inactive.</div>
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
        document.getElementById('enable-meta').addEventListener('change', (e) => {
            document.getElementById('meta-model-group').style.display = e.target.checked ? 'block' : 'none';
        });
    });

    async function loadDomains() {
        const resp = await fetch('/api/domains');
        const data = await resp.json();
        const select = document.getElementById('domain-select');
        select.innerHTML = '<option value="generic">Generic (auto-detect)</option>';
        data.domains.forEach(d => {
            const opt = document.createElement('option');
            opt.value = d.name;
            opt.textContent = `${d.name} (${d.language})`;
            select.appendChild(opt);
        });
    }

    async function loadLeaderboard() {
        const resp = await fetch('/api/leaderboard');
        const data = await resp.json();
        const container = document.getElementById('leaderboard-content');
        if (!data.leaderboard || data.leaderboard.length === 0) {
            container.innerHTML = '<div style="color: var(--text-dim); font-size: 12px;">No battles yet.</div>';
            return;
        }
        container.innerHTML = data.leaderboard.map((item, i) => `
            <div class="leaderboard-item">
                <span class="model">#${i+1} ${item.model}</span>
                <span class="elo">${item.elo_rating.toFixed(0)} ELO</span>
            </div>
        `).join('');
    }

    function startBattle() {
        const task = document.getElementById('task-description').value.trim();
        if (!task) { alert('Enter a task description'); return; }
        const config = {
            task_description: task,
            domain: document.getElementById('domain-select').value,
            side_a_model: document.getElementById('side-a-model').value,
            side_b_model: document.getElementById('side-b-model').value,
            judge_model: document.getElementById('judge-model').value,
            meta_model: document.getElementById('enable-meta').checked ? document.getElementById('meta-model').value : '',
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
        const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
        ws = new WebSocket(`${protocol}//${location.host}/ws/battle`);
        document.getElementById('start-btn').disabled = true;
        document.getElementById('start-btn').textContent = 'BATTLE IN PROGRESS...';
        document.getElementById('arena-content').innerHTML = '';
        ws.onopen = () => { ws.send(JSON.stringify(config)); };
        ws.onmessage = (event) => { handleEvent(JSON.parse(event.data)); };
        ws.onclose = () => {
            document.getElementById('start-btn').disabled = false;
            document.getElementById('start-btn').textContent = 'START BATTLE';
        };
        ws.onerror = () => {
            document.getElementById('start-btn').disabled = false;
            document.getElementById('start-btn').textContent = 'START BATTLE';
        };
    }

    function handleEvent(data) {
        const arena = document.getElementById('arena-content');
        switch(data.type) {
            case 'battle_start':
                arena.innerHTML = `<div class="status-bar">⚔️ Battle started — Domain: ${data.domain} — Task ID: ${data.task_id}</div>`;
                currentBattleData = {taskId: data.task_id, rounds: {}};
                break;
            case 'continuation':
                arena.innerHTML += `<div class="status-bar">📂 Resuming from round ${data.resumed_from_round}</div>`;
                break;
            case 'round_start':
                arena.innerHTML += `<div class="round-header">━━ Round <span>${data.round}</span> ━━</div>`;
                break;
            case 'code_generated':
                var sideKey = data.side.toLowerCase();
                var card = document.createElement('div');
                card.className = `card ${sideKey}-side`;
                card.id = `round-${data.round}-side-${sideKey}`;
                card.innerHTML = `<div class="card-header"><div class="card-title">Side ${data.side} ${data.side === 'A' ? '🔵' : '🟣'}</div><div class="loading"><span class="spinner"></span> Generating...</div></div><div class="card-model">${data.model}</div><pre class="card-code">${escapeHtml(data.code_preview)}...</pre>`;
                arena.appendChild(card);
                break;
            case 'verdict':
                updateCard(data);
                break;
            case 'round_result':
                var resultDiv = document.createElement('div');
                resultDiv.className = 'status-bar';
                resultDiv.innerHTML = `🏆 Round ${data.round} Winner: <strong style="color: var(--side-${data.winner.toLowerCase()})">Side ${data.winner}</strong> (${data.winner_model}) — Score: ${data.winner_score}/10 vs ${data.loser_score}/10`;
                arena.appendChild(resultDiv);
                loadLeaderboard();
                break;
            case 'meta_agent_start':
                var metaStart = document.createElement('div');
                metaStart.className = 'meta-banner';
                metaStart.id = `meta-${data.round}`;
                metaStart.innerHTML = `🧠 Meta-agent analyzing rounds 1-${data.round}...`;
                arena.appendChild(metaStart);
                break;
            case 'meta_agent_result':
                var metaLog = document.getElementById('meta-log');
                var entry = document.createElement('div');
                entry.className = 'lineage-item';
                entry.innerHTML = `Round ${data.round}: ${data.promoted ? '<span class="winner">PROMOTED</span>' : '<span class="card-banned">REVERTED</span>'} — Δ${(data.fitness_after - data.fitness_before).toFixed(2)}`;
                metaLog.appendChild(entry);
                var metaBanner = document.getElementById(`meta-${data.round}`);
                if (metaBanner) {
                    metaBanner.innerHTML = `🧠 Meta-agent ${data.promoted ? '<span class="promoted">PROMOTED</span>' : '<span class="reverted">REVERTED</span>'} changes — Fitness: ${data.fitness_before.toFixed(1)} → ${data.fitness_after.toFixed(1)} — ${data.summary}`;
                }
                break;
            case 'stability_reached':
                arena.innerHTML += `<div class="status-bar" style="color: var(--success);">✅ STABILITY REACHED at round ${data.round} — score ${data.score}/10</div>`;
                break;
            case 'battle_end':
                var endDiv = document.createElement('div');
                endDiv.className = 'status-bar';
                endDiv.style.borderColor = 'var(--success)';
                endDiv.innerHTML = `🏁 Battle complete — ${data.total_rounds} rounds — Winner: ${data.final_winner} (${data.final_score}/10)<br><br><button class="btn-secondary" onclick="copyCode()">📋 Copy Winning Code</button><button class="btn-secondary" onclick="downloadCode()">💾 Download Code</button>`;
                arena.appendChild(endDiv);
                currentBattleData.finalCode = data.final_code;
                break;
            case 'error':
                arena.innerHTML += `<div class="status-bar" style="color: var(--danger);">❌ Error: ${data.message || data.error}</div>`;
                break;
            case 'complete':
                document.getElementById('start-btn').disabled = false;
                document.getElementById('start-btn').textContent = 'START BATTLE';
                break;
        }
        arena.scrollTop = arena.scrollHeight;
        document.getElementById('arena-panel').scrollTop = arena.scrollHeight;
    }

    function updateCard(data) {
        var sideKey = data.side.toLowerCase();
        var card = document.getElementById(`round-${data.round}-side-${sideKey}`);
        if (!card) return;
        var scoreClass = data.score >= 7 ? 'high' : data.score >= 4 ? 'mid' : 'low';
        var scoreHtml = `<div class="card-score ${scoreClass}">${data.score}/10</div>`;
        var verdictHtml = `<div class="card-verdict">${data.reasoning}</div>`;
        if (data.banned_hits && data.banned_hits.length > 0) verdictHtml += `<div class="card-banned">❌ BANNED: ${data.banned_hits.join(', ')}</div>`;
        if (data.compile_success === false) verdictHtml += `<div class="card-banned">💥 COMPILATION FAILED</div>`;
        else if (data.compile_success === true) verdictHtml += `<div style="color: var(--success);">✅ Compiled</div>`;
        if (data.test_success === true) verdictHtml += `<div style="color: var(--success);">✅ Tests passed</div>`;
        else if (data.test_success === false) verdictHtml += `<div class="card-banned">❌ Tests failed</div>`;
        card.querySelector('.loading').innerHTML = scoreHtml;
        card.querySelector('.card-verdict')?.remove();
        card.innerHTML += verdictHtml;
    }

    function escapeHtml(text) {
        var div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    function copyCode() {
        if (currentBattleData.finalCode) {
            navigator.clipboard.writeText(currentBattleData.finalCode);
            alert('Winning code copied to clipboard!');
        }
    }

    function downloadCode() {
        if (currentBattleData.finalCode) {
            var blob = new Blob([currentBattleData.finalCode], {type: 'text/plain'});
            var a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = 'winning_code.txt';
            a.click();
        }
    }
</script>
</body>
</html>
HTMLEOF

# ─── README.md ───
cat > "$PROJECT_DIR/README.md" << 'MDEOF'
# 🧬 EvoCoder — Autonomous Evolutionary Coding Engine

Two LLMs enter. One survives. The judge evolves. No human babysitting required.

## Quick Start

```bash
cd evocoder
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000
