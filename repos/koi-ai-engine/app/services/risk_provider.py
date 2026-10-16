"""Per-turn risk input provider for exercise-director integration."""

import logging
import os

logger = logging.getLogger(__name__)


def validate_startup() -> None:
    if os.getenv("KOI_RISK_SOURCE") == "demo_lexicon":
        logger.warning("DEMO RISK SOURCE ACTIVE: word list, not crisis detection")


def get_risk(text: str):
    """Return ``(tier, score, flags)`` or unavailable risk input."""
    if os.getenv("KOI_RISK_SOURCE") != "demo_lexicon":
        return None, None, None

    import sys
    from pathlib import Path

    policy_dir = Path(__file__).resolve().parents[2] / "koi_policy"
    if str(policy_dir) not in sys.path:
        sys.path.insert(0, str(policy_dir))
    import intents

    if intents.distress(text):
        return "HIGH", 0.9, ["demo_distress"]
    return "LOW", 0.1, []
