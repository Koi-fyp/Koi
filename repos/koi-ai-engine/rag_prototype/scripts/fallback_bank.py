"""
Deterministic fallback content for intervention_content (source: "fallback"). M2, Oct 13 2026.

STATUS: DRAFT written by Claude. Not reviewed by a clinician; the Urdu and Roman Urdu text is NOT checked by a
native speaker. UX Flows v1.1 Flow 4 contains no sequence text (its v1.4 addition says so), so there was no canon
wording to copy. review_status on every item says "draft-unreviewed" so this is visible downstream.

Phone numbers (checked Oct 13 2026 against the sources below; none was test-called):
  1166  Sehat Tahaffuz national health helpline, federal (Ministry of National Health Services); Humraaz service
        connects callers with counsellors or hospitals. NOT described as a suicide/crisis line; hours not published.
        Sources: Dawn 2023 (dawn.com/news/1746472, "the toll free helpline 1166 is also active");
                 TherapyRoute, Aug 2026 (therapyroute.com/article/suicide-hotlines-and-crisis-lines-in-pakistan...).
  1122  Rescue/ambulance (provincial; availability depends on location). 15 Police. 115 Edhi ambulance.
  Taskeen +92 316 827 5336, free phone support, Mon-Sat 11 AM - 11 PM (TherapyRoute, Aug 2026).
  The same source states Pakistan has no round-the-clock mental-health helpline.

Languages follow the contract values: en, ur, ur-roman, mixed (= English followed by Urdu, per item).
"""

HELPLINE = {"name": "Humraaz (Sehat Tahaffuz 1166)", "number": "1166"}

_TEXT = {
    "en": [
        "I'm really glad you told me. What you're going through sounds very hard, and you don't have to face it "
        "alone right now.",
        "If you might act on thoughts of harming yourself, or you are in danger right now, please call 1122 (Rescue) "
        "or 15 (Police), or go to the nearest hospital emergency department. Edhi ambulance: 115.",
        "You can also talk to someone today: the Sehat Tahaffuz helpline 1166 (free; its Humraaz service can connect "
        "you to a counsellor), or Taskeen on 0316 8275336 (Monday to Saturday, 11 am to 11 pm). If you can, tell "
        "someone you trust how you are feeling.",
    ],
    "ur": [
        "مجھے خوشی ہے کہ آپ نے مجھے بتایا۔ آپ جس مشکل سے گزر رہے ہیں وہ بہت بھاری لگتی ہے، اور اس وقت آپ کو "
        "اکیلے اس کا سامنا نہیں کرنا۔",
        "اگر آپ کو لگتا ہے کہ آپ خود کو نقصان پہنچا سکتے ہیں یا آپ اس وقت خطرے میں ہیں تو براہِ کرم فوراً 1122 "
        "(ریسکیو) یا 15 (پولیس) پر کال کریں، یا قریبی ہسپتال کی ایمرجنسی میں جائیں۔ ایدھی ایمبولینس: 115۔",
        "آپ آج ہی کسی سے بات بھی کر سکتے ہیں: صحت تحفظ ہیلپ لائن 1166 (مفت؛ اس کی ہمراز سروس آپ کو کسی کاؤنسلر "
        "سے ملا سکتی ہے)، یا تسکین: 0316 8275336 (پیر تا ہفتہ، صبح 11 سے رات 11 بجے تک)۔ اگر ممکن ہو تو کسی "
        "قابلِ اعتماد شخص کو بتائیں کہ آپ کیسا محسوس کر رہے ہیں۔",
    ],
    "ur-roman": [
        "Mujhe khushi hai ke aap ne mujhe bataya. Aap jis mushkil se guzar rahe hain woh bohat bhaari lagti hai, "
        "aur is waqt aap ko akele iska saamna nahi karna.",
        "Agar aap ko lagta hai ke aap khud ko nuqsan pohncha sakte hain ya aap is waqt khatre mein hain, to barah-e-"
        "karam foran 1122 (Rescue) ya 15 (Police) par call karein, ya qareebi hospital ki emergency mein jaayein. "
        "Edhi ambulance: 115.",
        "Aap aaj hi kisi se baat bhi kar sakte hain: Sehat Tahaffuz helpline 1166 (muft; iski Humraaz service aap ko "
        "kisi counsellor se mila sakti hai), ya Taskeen: 0316 8275336 (Peer se Hafta, subah 11 se raat 11 baje "
        "tak). Agar mumkin ho to kisi bharosemand shakhs ko batayein ke aap kaisa mehsoos kar rahe hain.",
    ],
}
_TEXT["mixed"] = [en + "\n" + ur for en, ur in zip(_TEXT["en"], _TEXT["ur"])]

LANGUAGES = tuple(_TEXT)


def fallback(language):
    """List of contract items (<= 3) for the contract language. Unknown language -> English (never empty)."""
    lang = language if language in _TEXT else "en"
    return [{"text": t, "chunk_id": f"fallback.{lang}.{n}", "source_corpus": "deterministic",
             "evidence_role": None, "review_status": "draft-unreviewed"}
            for n, t in enumerate(_TEXT[lang], 1)]
