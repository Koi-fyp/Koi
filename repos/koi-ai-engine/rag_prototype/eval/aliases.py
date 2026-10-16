"""Synthetic user-voice aliases for the 26 authoritative chunks (doc2query-style INDEX KEYS).

PROVENANCE: written by Claude on 2026-10-12, in one pass, NOT native-reviewed, NOT clinician-reviewed.
Tag: claude-written-unreviewed. Urdu-script strings need a native read before any claim about Urdu.
Exactly 4 per chunk (en / roman Urdu / Urdu script / code-switched) so no chunk gains from having more aliases.

Rules followed: an alias is what a user might SAY that this chunk could answer; it never adds advice that is
not in the chunk. Several chunks are provider-directed (SAMHSA service-design principles, media campaigns),
and aliases for them are a stretch -- that is why the harness reports alias arms separately on hub and
non-hub rows, and why a good alias score on those chunks is NOT evidence they are fit to show a user.

Leakage: these were written from the chunk text. Claude had seen the dev queries earlier in the session, so
independence from the dev set is partial. eval/super_run.py prints a near-duplicate check (alias vs dev
query). The holdout split was never used to write or tune anything here.
"""

ALIAS_PROVENANCE = "claude-written-unreviewed"

ALIASES = {
    "who_a53d6078d3": [
        "I want to make a plan for what to do when thoughts of ending my life get strong",
        "Jab khudkushi ke khayal tez ho jayen to mujhe pehle se koi safety plan banana hai",
        "جب خود کو ختم کرنے کے خیالات بڑھ جائیں تو میں پہلے سے ایک حفاظتی منصوبہ بنانا چاہتا ہوں",
        "mujhe ek safety plan chahiye jo mere dark thoughts ke time pe kaam aaye",
    ],
    "who_262440fba5": [
        "Do awareness campaigns about suicide actually stop people from dying?",
        "Kya suicide ke baare mein awareness campaigns se waqai farq parta hai?",
        "کیا خودکشی کے بارے میں آگاہی مہمات سے واقعی لوگوں کی جان بچتی ہے؟",
        "awareness campaigns aur posters se kya suicide rukti hai ya sirf dikhawa hai?",
    ],
    "who_466ea20335": [
        "Can an app with CBT or mindfulness exercises help me when I have suicidal thoughts?",
        "Kya koi app jo CBT ya mindfulness sikhaye, khudkushi ke khayalon mein madad kar sakti hai?",
        "کیا کوئی ایپ جو ذہنی مشقیں اور مائنڈفلنس سکھائے خودکشی کے خیالات میں مدد کر سکتی ہے؟",
        "kya online therapy app ya mindfulness exercises se meri dark thoughts kam ho sakti hain?",
    ],
    "who_bea4d647aa": [
        "What counts as self-harm? I hurt myself sometimes",
        "Khud ko nuqsan pohanchana ya zakhmi karna self-harm mein kya kya aata hai?",
        "خود کو نقصان پہنچانا یا زخمی کرنا کسے کہتے ہیں؟",
        "main kabhi kabhi khud ko hurt kar leta hun, kya yeh self-harm kehlata hai?",
    ],
    "who_250f535470": [
        "I keep thinking I would be better off dead, is that suicidal thoughts?",
        "Mujhe lagta hai main mar jaun to behtar hoga, kya yeh suicidal thoughts hain?",
        "مجھے لگتا ہے کہ میرا مر جانا بہتر ہوگا، کیا یہ خودکشی کے خیالات ہیں؟",
        "baar baar sochta hun ke better off dead hun, is it called suicidal ideation?",
    ],
    "samhsa_e5b108d46d": [
        "Can the hotline, a mobile team and a hospital all work together to help me?",
        "Mujhe aisi madad chahiye jahan helpline, doctor aur hospital sab mil kar kaam karein",
        "مجھے ایسی مدد چاہیے جہاں ہیلپ لائن، ڈاکٹر اور ہسپتال سب مل کر کام کریں",
        "helpline, hospital aur family sab coordinate karke meri help kar sakte hain kya?",
    ],
    "samhsa_c65d0b35bb": [
        "I should decide what counts as my crisis, and my family joins only if I want",
        "Mera crisis kya hai yeh main tay karunga, aur family ko meri marzi se shamil karna",
        "میرا بحران کیا ہے یہ میں خود طے کروں گا اور گھر والوں کو میری مرضی سے شامل کیا جائے",
        "meri problem kitni serious hai yeh mujhe define karne do, family ko apni marzi se involve karna hai",
    ],
    "samhsa_983fdc952b": [
        "I want to feel safe and not be forced or locked up when I ask for help",
        "Madad maangne par mujhe zabardasti band kamray mein na rakha jaye, mujhe mehfooz mehsoos ho",
        "مدد مانگنے پر مجھے زبردستی کہیں بند نہ کیا جائے، میں محفوظ محسوس کرنا چاہتا ہوں",
        "help maangne pe force ya restraint nahi chahiye, mujhe safe environment chahiye",
    ],
    "samhsa_07f07c54c2": [
        "I live in a village and feel these services are not made for people like me",
        "Main gaon mein rehta hun aur lagta hai yeh sehat ki sahulatein mere jaise logon ke liye nahi",
        "میں گاؤں میں رہتا ہوں اور لگتا ہے کہ یہ سہولتیں مجھ جیسے لوگوں کے لیے نہیں ہیں",
        "disability ya remote area ki wajah se mujhe mental health help milna mushkil hai",
    ],
    "samhsa_39eaeaebcb": [
        "Does anyone check whether crisis services actually work and learn from deaths?",
        "Kya koi dekhta hai ke crisis services waqai kaam kar rahi hain ya nahi?",
        "کیا کوئی دیکھتا ہے کہ بحران کی خدمات واقعی کام کر رہی ہیں یا نہیں؟",
        "crisis services ki quality aur effectiveness ka data kaun track karta hai?",
    ],
    "samhsa_ba841557a7": [
        "I am a teenager and I do not want to be taken away from home when I am in crisis",
        "Main teenager hun aur crisis mein mujhe ghar se door nahi bheja jaye",
        "میں نوعمر ہوں اور بحران میں مجھے گھر سے دور نہ بھیجا جائے",
        "teen hone ki wajah se mujhe family ke saath ghar pe hi support chahiye, hospital nahi",
    ],
    "samhsa_d8ce247ecc": [
        "I want help that looks at my strengths, and maybe someone who has been through it",
        "Mujhe aisi madad chahiye jo meri khubiyon par focus kare, aur jis ne khud yeh sab jhela ho woh baat kare",
        "مجھے ایسی مدد چاہیے جو میری خوبیوں پر توجہ دے اور جس نے خود یہ سب جھیلا ہو وہ مجھ سے بات کرے",
        "peer support chahiye, koi jo recovery se guzra ho aur meri strengths dekhe",
    ],
    "samhsa_21fe845e34": [
        "People ask what is wrong with me, but what happened to me is what matters",
        "Log poochte hain mujh mein kya kharabi hai, koi yeh nahi poochta ke mere saath kya hua",
        "لوگ پوچھتے ہیں مجھ میں کیا خرابی ہے، کوئی نہیں پوچھتا کہ میرے ساتھ کیا ہوا",
        "meri childhood ke trauma ki wajah se meri behavior aisi hai, mujhe judge mat karo",
    ],
    "samhsa_8ebc7bced3": [
        "After the worst night passes, who will keep checking on me?",
        "Bura waqt guzar jaye to uske baad bhi mujhe follow-up aur support milti rahe",
        "بُرا وقت گزر جانے کے بعد بھی مجھے مسلسل مدد اور فالو اپ ملتا رہے",
        "crisis ke baad bhi continuous support aur follow-up chahiye, kisi bhi door se help mil jaye",
    ],
    "samhsa_28a1f6c98e": [
        "Is the help you offer based on proven research or just opinions?",
        "Jo madad mil rahi hai woh research aur saboot par mabni hai ya sirf andaza?",
        "جو مدد ملتی ہے وہ تحقیق اور ثبوت پر مبنی ہے یا صرف اندازہ؟",
        "evidence-based treatment hi chahiye, trained staff ke saath",
    ],
    "samhsa_38dea1e07c": [
        "I also have a medical condition and a disability, will anyone understand my whole situation?",
        "Mujhe medical bimari bhi hai aur disability bhi, kya koi meri poori halat samjhega?",
        "مجھے طبی بیماری بھی ہے اور معذوری بھی، کیا کوئی میری پوری صورتحال سمجھے گا؟",
        "mere medical conditions aur disability ke saath mental health support kaise milega?",
    ],
    "samhsa_068757d34a": [
        "Is there a hotline I can call or text to talk to a live person any time?",
        "Kya koi helpline hai jis par main kisi bhi waqt call ya text karke kisi insaan se baat kar sakun?",
        "کیا کوئی ہیلپ لائن ہے جس پر میں کسی بھی وقت کال یا میسج کر کے کسی انسان سے بات کر سکوں؟",
        "koi crisis helpline number chahiye jahan call ya chat pe live person mile",
    ],
    "samhsa_0a88eb2fc9": [
        "Do crisis hotlines actually make people feel better after they talk?",
        "Kya helpline pe baat karne se log waqai behtar mehsoos karte hain?",
        "کیا ہیلپ لائن پر بات کرنے سے لوگ واقعی بہتر محسوس کرتے ہیں؟",
        "helpline pe baat karna kaam karta hai ya time waste hai, koi research hai?",
    ],
    "samhsa_c744348b34": [
        "What questions do counsellors ask to check if someone is thinking about suicide?",
        "Counsellor yeh kaise puchte hain ke kya aap khudkushi ke baare mein soch rahe hain?",
        "مشیر یہ کیسے پوچھتے ہیں کہ کیا آپ خودکشی کے بارے میں سوچ رہے ہیں؟",
        "suicide risk assessment ke questions kya hote hain jo hotline wale puchte hain?",
    ],
    "mhgappk_bf203e39f6": [
        "I feel hopeless about the future and sometimes think life is not worth living",
        "Mujhe mustaqbil se koi umeed nahi aur lagta hai zindagi jeene ke qabil nahi",
        "مجھے مستقبل سے کوئی امید نہیں اور لگتا ہے زندگی جینے کے قابل نہیں",
        "future ki koi hope nahi, kabhi kabhi sochta hun life jeene ka koi faida nahi",
    ],
    "mhgappk_11f0557fbc": [
        "My biggest worry is my family situation and I do not know who to talk to",
        "Meri sab se bari pareshani ghar ka maahaul hai aur samajh nahi aata kis se baat karun",
        "میری سب سے بڑی پریشانی گھر کے حالات ہیں اور سمجھ نہیں آتا کس سے بات کروں",
        "mujhe bohat worry hai aur koi nahi jis se apni problems share karun",
    ],
    "mhgappk_480c27df26": [
        "When I am upset there is nobody I feel I can lean on",
        "Jab main pareshan hota hun to koi aisa nahi jis par sahara kar sakun",
        "جب میں پریشان ہوتا ہوں تو کوئی نہیں جس کا سہارا لے سکوں",
        "main akela feel karta hun, koi support nahi hai, kis se baat karun?",
    ],
    "mhgappk_bfba6f6671": [
        "I am under so much stress and do not know how to handle it",
        "Mujh par bohat zehni dabao hai aur samajh nahi aata isse kaise nimtun",
        "مجھ پر بہت ذہنی دباؤ ہے اور سمجھ نہیں آتا اس سے کیسے نمٹوں",
        "exams aur ghar ka stress itna hai ke handle nahi ho raha",
    ],
    "mhgappk_028b8b03ca": [
        "My condition is long term, how do I keep up care with my family helping?",
        "Meri bimari lambi chalne wali hai, ghar walon ke saath mil kar ilaj ka plan kaise banaun?",
        "میری بیماری طویل مدتی ہے، گھر والوں کے ساتھ مل کر علاج کا منصوبہ کیسے بناؤں؟",
        "chronic mental health condition ke liye family ke saath management plan chahiye",
    ],
    "mhgappk_8ae903049e": [
        "Someone at home hurts me and I am scared to tell anyone",
        "Ghar mein koi mujhe marta peetta hai aur main kisi ko batane se darta hun",
        "گھر میں کوئی مجھے مارتا پیٹتا ہے اور میں کسی کو بتانے سے ڈرتا ہوں",
        "domestic violence ho rahi hai mere saath, kisi se share karne mein dar lagta hai",
    ],
    "mhgappk_4174e3caad": [
        "I am exhausted looking after my sick mother and nobody asks how I am",
        "Main apni bimar ammi ki dekhbhal karke thak gaya hun aur koi mujh se nahi poochta",
        "میں اپنی بیمار والدہ کی دیکھ بھال سے تھک گیا ہوں اور کوئی مجھ سے حال نہیں پوچھتا",
        "carer burnout ho gaya hai, ghar mein patient ki care karte karte main khud toot gaya",
    ],
}
