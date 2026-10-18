"""Pure-Python validator for Rhubarb Lip Sync mouth-cue output.

Mirrors (and is stricter than) the checks in the existing client/dev code:
  - src/lib/speech/mouthCues.ts parseMouthCues: finite, ordered, non-overlapping,
    end > start (unknown values are coerced to X there; here they are an error).
  - dev/avatar-sandbox/voice_service.py: cue end <= duration + 0.05 s and
    value in 'ABCDEFGHX'.
  - src/lib/speech/voiceContract.ts: no cue may end after duration + 0.05 s.

No third-party imports. Usable as a library or CLI:
    python cue_validator.py cues.json [audio_duration_seconds]
"""
from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass, field

VALID_SHAPES = frozenset("ABCDEFGHX")
# Same 50 ms tolerance the existing worker and client use for Rhubarb rounding.
DEFAULT_TOLERANCE_S = 0.05


@dataclass
class CueReport:
    ok: bool
    errors: list[str] = field(default_factory=list)
    cue_count: int = 0
    first_start: float | None = None
    last_end: float | None = None
    covered_s: float = 0.0  # sum of cue lengths
    max_gap_s: float = 0.0  # largest hole between consecutive cues
    shape_counts: dict[str, int] = field(default_factory=dict)

    def summary(self) -> str:
        if self.ok:
            return f"ok ({self.cue_count} cues, last_end={self.last_end})"
        return "; ".join(self.errors)


def _is_number(value) -> bool:
    # bool is an int subclass; JSON true/false must not pass as a time.
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate_cues(
    cues,
    audio_duration: float | None = None,
    tolerance: float = DEFAULT_TOLERANCE_S,
    allow_empty: bool = False,
    max_gap: float | None = None,
) -> CueReport:
    """Validate a list of {start, end, value} cues.

    Checks: list shape; numeric finite times; start >= 0; end > start;
    start >= previous end (monotonic, non-overlapping; touching is allowed);
    value in A-H/X. With audio_duration: every end <= duration + tolerance
    (bounds), first start <= tolerance and last end >= duration - tolerance
    (coverage). With max_gap: no hole between cues larger than max_gap.
    """
    report = CueReport(ok=False)
    errors = report.errors

    if not isinstance(cues, list):
        errors.append("cues must be a list")
        return report
    if audio_duration is not None and (not _is_number(audio_duration) or audio_duration < 0):
        errors.append("audio_duration must be a finite non-negative number")
        return report
    if not cues:
        if not allow_empty:
            errors.append("no cues")
        report.ok = not errors
        return report

    previous_end = 0.0
    for index, cue in enumerate(cues):
        where = f"cue[{index}]"
        if not isinstance(cue, dict):
            errors.append(f"{where}: not an object")
            continue
        start, end, value = cue.get("start"), cue.get("end"), cue.get("value")
        if not _is_number(start) or not _is_number(end):
            errors.append(f"{where}: start/end must be finite numbers")
            continue
        if start < 0:
            errors.append(f"{where}: negative start {start}")
        if end <= start:
            errors.append(f"{where}: end {end} <= start {start}")
        if start < previous_end:
            errors.append(f"{where}: start {start} overlaps previous end {previous_end}")
        elif index and start - previous_end > report.max_gap_s:
            report.max_gap_s = start - previous_end
        if not isinstance(value, str) or value not in VALID_SHAPES:
            errors.append(f"{where}: invalid shape {value!r}")
        else:
            report.shape_counts[value] = report.shape_counts.get(value, 0) + 1
        if audio_duration is not None and end > audio_duration + tolerance:
            errors.append(f"{where}: end {end} beyond audio duration {audio_duration} (+{tolerance})")
        if end > start:
            report.covered_s += end - start
        if report.first_start is None:
            report.first_start = start
        previous_end = max(previous_end, end)

    report.cue_count = len(cues)
    report.last_end = previous_end
    if audio_duration is not None and report.first_start is not None:
        if report.first_start > tolerance:
            errors.append(f"coverage: first cue starts at {report.first_start} (> {tolerance})")
        if report.last_end < audio_duration - tolerance:
            errors.append(f"coverage: last cue ends at {report.last_end}, audio is {audio_duration} (-{tolerance})")
    if max_gap is not None and report.max_gap_s > max_gap:
        errors.append(f"gap: {report.max_gap_s:.3f}s between cues exceeds {max_gap}s")

    report.covered_s = round(report.covered_s, 6)
    report.max_gap_s = round(report.max_gap_s, 6)
    report.ok = not errors
    return report


def validate_rhubarb_document(document, audio_duration: float | None = None, **kwargs) -> CueReport:
    """Validate a parsed Rhubarb `-f json` document ({"metadata": ..., "mouthCues": [...]})."""
    if not isinstance(document, dict) or "mouthCues" not in document:
        return CueReport(ok=False, errors=["document has no mouthCues"])
    return validate_cues(document["mouthCues"], audio_duration, **kwargs)


def validate_rhubarb_file(path, audio_duration: float | None = None, **kwargs) -> CueReport:
    try:
        with open(path, encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, ValueError) as exc:
        return CueReport(ok=False, errors=[f"unreadable cue file: {type(exc).__name__}"])
    return validate_rhubarb_document(document, audio_duration, **kwargs)


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        sys.exit(2)
    result = validate_rhubarb_file(sys.argv[1], float(sys.argv[2]) if len(sys.argv) == 3 else None)
    print(result.summary())
    sys.exit(0 if result.ok else 1)
