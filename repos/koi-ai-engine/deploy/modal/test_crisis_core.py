"""Direct, dependency-light tests for the crisis scoring contract."""
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import koi_crisis_core as core


class CrisisCoreTests(unittest.TestCase):
    def setUp(self):
        self.cal = dict(core.UNCALIBRATED)
        self.cal["max_category"] = "HIGH"
        self.helpline = {
            "name": "Sehat Tahaffuz 1166 (Humraaz mental health service)",
            "number": "1166",
            "verified": False,
        }

    def test_bands_and_high_cap(self):
        self.assertEqual(core.category(0.1, max_category="HIGH"), "LOW")
        self.assertEqual(core.category(0.4, max_category="HIGH"), "MODERATE")
        self.assertEqual(core.category(0.7, max_category="HIGH"), "HIGH")
        self.assertEqual(core.category(0.99, max_category="HIGH"), "HIGH")

    def test_intervention_rules_and_fallback(self):
        grounded = {"source": "grounded", "items": [{"text": "Stay with someone."}]}
        self.assertIsNone(core.intervention("MODERATE", grounded, self.helpline))
        self.assertEqual(core.intervention("HIGH", grounded, self.helpline)["source"], "grounded")
        self.assertEqual(core.intervention("CRITICAL", grounded, self.helpline)["source"], "fallback")
        self.assertEqual(core.intervention("HIGH", {"source": "bad"}, self.helpline)["source"], "fallback")
        self.assertEqual(core.intervention("HIGH", None, self.helpline)["helpline"], self.helpline)

    def test_trigger_flags_require_audio(self):
        self.assertEqual(core.trigger_flags("T", 0.1, 0.9), [])
        self.assertEqual(core.trigger_flags("TA", 0.1, 0.9), ["vocal_contradiction"])
        self.assertEqual(core.trigger_flags("TA", 0.9, 0.9), [])

    def test_confidence_reasons(self):
        confidence, reasons = core.confidence("TA", 0.9, 0.2, self.cal, False)
        self.assertEqual(confidence, "reduced")
        self.assertEqual(
            reasons,
            ["reduced_modality_set", "text_model_uncertain", "ensemble_disagreement", "uncalibrated"],
        )

    def test_score_turn_is_finite_and_capped(self):
        out = core.score_turn(np.array([0.0, 0.0, 5.0, 0.0, 0.0, 0.0, 0.0]), "T", None, self.cal, False)
        self.assertTrue(0.0 <= out["crisis_score"] <= 1.0)
        self.assertEqual(out["risk_category"], "HIGH")


if __name__ == "__main__":
    unittest.main()
