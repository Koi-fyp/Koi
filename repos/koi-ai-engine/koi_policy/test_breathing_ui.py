"""Headless check of the exercises reference page (needs Playwright + Chromium).   Run: python test_breathing_ui.py"""
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

import catalogue as C

HERE = Path(__file__).resolve().parent
PAGE = HERE / "breathing_reference.html"
CATS = {l: C.localize(C.load(), C.load_i18n(), l) for l in C.LANGS}
fails = []


def check(n, c):
    print(("PASS " if c else "FAIL ") + n)
    if not c:
        fails.append(n)


def btn(pg, name):
    return pg.get_by_role("button", name=name, exact=True).first


def lib(pg, ex_id):
    pg.locator(f'#library button[data-id="{ex_id}"]').click()


with sync_playwright() as pw:
    b = pw.chromium.launch()
    for reduced in ("no-preference", "reduce"):
        pg = b.new_page(viewport={"width": 375, "height": 740}, reduced_motion=reduced)
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.on("console", lambda m: errs.append(m.text) if m.type == "error" else None)
        pg.goto(PAGE.as_uri())
        t = f"[{reduced}] "
        check(t + "offer shown", pg.is_visible("text=Would you like to try a short breathing exercise"))
        btn(pg, "What is it?").click()
        check(t + "'What is it?' explains (UX Flow 10 branch)", pg.is_visible("text=about six breaths a minute"))
        btn(pg, "Yes, let's try").click()
        check(t + "breathing offers 1 or 5 minutes (Balban 2023)", pg.is_visible("text=1 minute") and pg.is_visible("text=5 minutes"))
        btn(pg, "1 minute").click(); pg.wait_for_timeout(600)
        check(t + "breathing starts with 'Breathe in'", pg.inner_text("#player .phase") == "Breathe in")
        check(t + "safety note visible", pg.is_visible("text=If you feel dizzy or more uneasy"))
        btn(pg, "Pause").click()
        c1 = pg.inner_text("#player .count"); pg.wait_for_timeout(1500); c2 = pg.inner_text("#player .count")
        check(t + "pause freezes the countdown", c1 == c2)
        btn(pg, "Resume").click(); pg.wait_for_timeout(4500)
        check(t + "4 s in then 'Breathe out' (6 breaths/min)", pg.inner_text("#player .phase") == "Breathe out")
        scale = pg.eval_on_selector(".orb", "e => e.style.transform")
        check(t + ("orb animation off" if reduced == "reduce" else "orb contracts on exhale"),
              scale == ("scale(0.85)" if reduced == "reduce" else "scale(0.7)"))
        btn(pg, "Stop").click()
        check(t + "stop -> post check", pg.is_visible("text=Stopped. That's completely fine."))
        check(t + "post check always offers 'Keep talking'", pg.get_by_role("button", name="Keep talking").count() >= 1)
        btn(pg, "Mood 2 of 5").click()
        check(t + "mood <= 2 -> offer to talk", pg.is_visible("text=Do you want to talk about what's going on?"))
        btn(pg, "Done").click()
        btn(pg, "Not now").click(); btn(pg, "Not the right moment").click()
        check(t + "'Not the right moment' -> short alternative + later", pg.is_visible("text=Unhooking from a thought") and pg.is_visible("text=Maybe later"))
        btn(pg, "Maybe later").click()
        btn(pg, "Not now").click(); btn(pg, "Breathing isn't for me").click()
        check(t + "'Breathing isn't for me' -> alternatives + 'Just keep talking'", pg.is_visible("text=Just keep talking"))
        btn(pg, "5-4-3-2-1 senses").click()
        for _ in range(5):
            btn(pg, "Next").click()
        check(t + "finishing steps -> mood check", pg.is_visible("text=How is your mood right now?"))
        btn(pg, "Skip").click()
        # cyclic sighing phases
        lib(pg, "cyclic_sighing"); btn(pg, "1 minute").click(); pg.wait_for_timeout(2500)
        check(t + "cyclic sighing: second short inhale phase", pg.inner_text("#player .phase") == "Short top-up breath in")
        btn(pg, "Stop").click(); btn(pg, "Skip").click()
        # thought check
        lib(pg, "thought_check")
        for a in ["Nobody wants to talk to me.", "80", "My friends didn't reply yesterday.", "My cousin called last week.",
                  "One quiet day doesn't mean nobody cares.", "Some people do care, even if they're busy.", "50"]:
            pg.locator("#player textarea, #player input").first.fill(a); btn(pg, "Next").click()
        check(t + "thought check shows belief 80 -> 50", pg.is_visible("text=Belief in the thought: 80 → 50"))
        btn(pg, CATS["en"]["exercises"][[e["id"] for e in CATS["en"]["exercises"]].index("thought_check")]["save"]).click()
        btn(pg, "Skip").click()
        # get going: 0-10 confidence, < 7 -> make smaller
        lib(pg, "pmplus_get_going")
        btn(pg, "A 10-minute walk outside").click(); btn(pg, "Next").click()
        pg.locator("#player textarea").fill("After Asr, around 5 pm"); btn(pg, "Next").click()
        check(t + "confidence is asked 0-10", pg.get_attribute("#player input", "max") == "10" and pg.get_attribute("#player input", "min") == "0")
        pg.locator("#player input").fill("6"); btn(pg, "Next").click()
        check(t + "confidence 6 (< 7) -> make it smaller (Brief Action Planning)", pg.is_visible("text=Let's make it a bit smaller"))
        btn(pg, "Stop").click(); btn(pg, "Skip").click()
        # problems: unchangeable -> coping
        lib(pg, "pmplus_managing_problems")
        pg.locator("#player textarea").fill("My exams are next week."); btn(pg, "Next").click(); btn(pg, "No").click()
        check(t + "unchangeable problem -> coping exercises offered", pg.is_visible("text=Some problems can't be changed right now"))
        btn(pg, "Stop").click(); btn(pg, "Skip").click()
        # social support: SUDS 0-100 asked
        lib(pg, "pmplus_social_support")
        btn(pg, "Next").click()
        check(t + "empty required answer does not advance", pg.is_visible("text=Question 1 of 5"))
        for a in ["My cousin Ali", "Send him a meme"]:
            pg.locator("#player textarea").fill(a); btn(pg, "Next").click()
        btn(pg, "Next").click()   # optional community question
        check(t + "Social Ladder SUDS 0-100 asked", pg.get_attribute("#player input", "max") == "100")
        btn(pg, "Stop").click(); btn(pg, "Skip").click()
        sw = pg.evaluate("document.documentElement.scrollWidth")
        check(t + "no horizontal scroll at 375 px", sw <= 375)
        check(t + "no JS errors", not errs)
        pg.close()

    # Urdu script and Roman Urdu
    pg = b.new_page(viewport={"width": 375, "height": 740})
    errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto(PAGE.as_uri())
    btn(pg, "اردو").click()
    ur = CATS["ur"]
    check("[ur] layout switches to right-to-left", pg.get_attribute("#app", "dir") == "rtl")
    check("[ur] offer text in Urdu script", pg.is_visible(f"text={ur['offer']['text']}"))
    btn(pg, ur["offer"]["buttons"][0]).click(); btn(pg, ur["exercises"][0]["duration_options"][0]["label"]).click()
    pg.wait_for_timeout(600)
    check("[ur] breathing phase label in Urdu", pg.inner_text("#player .phase") == ur["exercises"][0]["phases"][0]["label"])
    btn(pg, ur["ui"]["stop"]).click()
    check("[ur] post check and keep-talking in Urdu", pg.is_visible(f"text={ur['post_check']['text']}") and
          pg.get_by_role("button", name=ur["post_check"]["keep_talking"]).count() >= 1)
    btn(pg, ur["ui"]["skip"]).click()
    pg.locator('#library button[data-id="thought_check"]').click()
    check("[ur] thought check first question in Urdu", pg.is_visible(f"text={ur['exercises'][[e['id'] for e in ur['exercises']].index('thought_check')]['prompts'][0]['ask']}"))
    btn(pg, "Roman Urdu").click()
    ro = CATS["ur-roman"]
    check("[ur-roman] layout back to left-to-right", pg.get_attribute("#app", "dir") == "ltr")
    check("[ur-roman] offer in Roman Urdu with code-switching", pg.is_visible(f"text={ro['offer']['text']}") and "exercise" in ro["offer"]["text"])
    btn(pg, ro["offer"]["buttons"][2]).click()
    check("[ur-roman] decline follow-up in Roman Urdu", pg.is_visible(f"text={ro['decline_followup']['text']}"))
    sw = pg.evaluate("document.documentElement.scrollWidth")
    check("[ur/ur-roman] no horizontal scroll at 375 px", sw <= 375)
    check("[ur/ur-roman] no JS errors", not errs)
    pg.close()
    b.close()

print("\nALL PASSED" if not fails else "\nFAILED: " + ", ".join(fails))
sys.exit(1 if fails else 0)
