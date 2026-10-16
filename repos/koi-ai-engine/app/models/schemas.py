"""
🆕 [PHASE 2 REBUILD]

Schema below is the LOCKED /api/v1/chat contract exactly as specified in
KOI_ULTIMATE_MASTER_BLUEPRINT_v4_13.md §4.1 (lines 277-293) — not
invented or guessed:

    {
      "request": {
        "message": "string",
        "session_history": [{"role": "user", "content": "Hello"}]
      },
      "response": {
        "reply": "Hi there. How are you?",
        "companion_state": { "emotion": "joy", "intensity": 0.8 },
        "latency_ms": 150
      }
    }

🆕 FLAGGED, NOT RESOLVED — a real contradiction, not silently picked:
SESSION_HANDOFF.md §22.4 states the new endpoint must match chat.ts's
EXISTING deployed contract for a clean cutover: `{ reply, emotion,
crisis_flag, sentiment_score }` — flat `emotion`, plus `crisis_flag` and
`sentiment_score`, neither of which appear anywhere in the Blueprint's
locked schema above. `crisis_score`/`risk_category` belong to the
SEPARATE `/api/v1/crisis` endpoint per Blueprint §4.1's own structure,
not `/api/v1/chat` — chat.ts appears to expect crisis-adjacent fields on
the wrong endpoint's response, or a schema evolution occurred that never
made it into the Blueprint, or vice versa. I do not have chat.ts's actual
contents to resolve this, and won't guess a merged shape. Implementing
the BLUEPRINT'S schema here since it's canonical and dated. Reconciling
this against the real chat.ts is a required next step before the client
can actually consume this endpoint without changes.

The 32-class emotion taxonomy and the "5 strict VRoid blendshapes" it
maps to are referenced in Blueprint §4.1 but not enumerated anywhere in
canon I have access to — `emotion` is typed as a free-form `str` here,
not a constrained enum, because inventing that 32-item list myself would
be exactly the kind of unstated-assumption-filling this project's
grounding discipline exists to prevent. That taxonomy + the
32-to-5 mapping dictionary (Phase 2 line 150) is a separate, real, open
task.
"""

from typing import List, Literal, Optional

from pydantic import BaseModel, Field


class SessionTurn(BaseModel):
    role: Literal['user', 'assistant']
    content: str


class ChatRequest(BaseModel):
    message: str = Field(min_length=1)
    session_history: List[SessionTurn] = Field(default_factory=list)
    exercise_state: Optional[str] = None
    client_event: Optional[
        Literal[
            'none',
            'playback_done',
            'playback_stopped',
            'start_breathing',
            'start_grounding',
            'start_plan',
        ]
    ] = None


class CompanionState(BaseModel):
    emotion: str
    intensity: float = Field(ge=0.0, le=1.0)


class ChatResponse(BaseModel):
    companion_state: CompanionState
    reply: str
    latency_ms: int
    exercise_state: Optional[str] = None
    ui_action: Optional[dict] = None
    handoff: Optional[str] = None


# ---- system endpoints (unchanged in shape from before) ----


class HealthStatus(BaseModel):
    status: str
    service: str = 'koi-ai-engine'
    version: str = '0.2.0'
    cpu_percent: float
    memory_percent: float
    memory_available_mb: int
    model_loaded: bool
    device: str
