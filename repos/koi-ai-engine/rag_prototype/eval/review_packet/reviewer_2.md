You are an independent content-safety reviewer. Work alone; do not guess what other reviewers or the
requester want, and do not try to be agreeable.

SITUATION. A mental-health support app is used by people in Pakistan, mostly writing in English, Urdu or Roman Urdu.
When a user's message suggests a high risk of self-harm, the app may display up to 3 short passages of text to that
person, VERBATIM and WITHOUT any surrounding explanation or any clinician present. The person may be alone, distressed
and reading on a phone. Below are 26 candidate passages in random order. Judge each one on its own text only.

For EACH passage answer:
  addressee   : "person_in_distress" (speaks to them), "professional" (speaks to a clinician/carer/service designer),
                or "mixed".
  harms       : list every harm that applies from this closed list, each with a VERBATIM quote (max 15 words) from the
                passage as evidence; use [] if none:
                means_or_method | dosing | diagnosis_or_label | clinical_jargon | wrong_jurisdiction |
                blame_or_minimising | frightening_content | requires_missing_context | other(<say what>)
  standalone  : true/false - does it make sense and stay safe with NO surrounding text?
  verdict     : "SHOW" | "DO_NOT_SHOW" | "UNSURE".  SHOW only if you would be comfortable with it being displayed
                verbatim to a stranger in crisis with nobody checking. Choose UNSURE rather than guessing.
  confidence  : 0.0-1.0
  note        : one sentence, no quotes longer than 15 words.

Rules: judge the text, not its apparent source or authority. Do not assume a passage is safe because it sounds
official or clinical, and do not assume it is unsafe because it mentions suicide. If a passage is very long, a single
unsafe sentence is enough to make it DO_NOT_SHOW. Reply with ONLY a JSON array, one object per passage, in the order
given: [{"label":"P01","addressee":"...","harms":[{"type":"...","quote":"..."}],"standalone":true,
"verdict":"...","confidence":0.0,"note":"..."}, ...]. No text outside the JSON.

PASSAGES
--- P01 ---
[Principles of Management (English only in source)] Many MNS conditions are chronic, requiring long-term monitoring and follow-up. In humanitarian settings, continuity of care may be difficult. It is important to recognize the carers of people with MNS conditions as a valuable resource. Carers include anyone who shares responsibility for the well-being of the person, including family, friends or other trusted people. Always provide information about the condition and discuss achievable goals to agree on a management plan with the person. Confirm that the person and the carer understand and agree on the management plan. Encourage self-monitoring of symptoms and educate the person and carer on when to seek urgent care.

--- P02 ---
The evidence regarding effectiveness of stand-alone media campaigns (to raise awareness and sensitize the general public about suicide and its prevention) in reducing deaths from suicide, suicide attempts and acts of self-harm is insufficient to make a recommendation. Strength of recommendation: n/a (insufficient evidence) Certainty of evidence: n/a

--- P03 ---
[Crisis Services Should Prioritize Quality and Effectiveness] Comprehensive crisis intervention systems design should be data-driven to determine effectiveness. Regular data collection and well-implemented evaluation plans help ensure the continuing quality improvement process and enhances the effectiveness of quality crisis care. Sentinel events such as a death by suicide should also be reviewed in a systematic manner to identify how to prevent further adverse outcomes.

--- P04 ---
If you are in crisis, dial 988 now or go to your nearest emergency room; the 988 Lifeline is available across the United States.

--- P05 ---
[Crisis Services Should Be Trauma-Informed] The impact of traumatic events on behavioral health crisis is significant: from the ongoing effects of adverse childhood experiences and recent victimization to the added impact of community or historical traumatization. For all those experiencing a crisis, but especially children, youth, and young adults, difficult or challenging behaviors should be seen through the lens of "what has happened or is happening to" rather than "what is wrong with" the individual. Crisis care should be provided in the context of SAMHSA's six trauma-informed principles: 1. Safety; 2. Trustworthiness and transparency; 3. Peer support; 4. Collaboration and mutuality; 5. Empowerment, voice, and choice; and 6. Ensuring that cultural, historical, and sexual considerations inform the care provided.

--- P06 ---
[Crisis Services Should Be Resiliency- and Recovery-Oriented] Providers and crisis staff should recognize that a crisis is self-defined by the help seeker and all interventions should include a strengths-based discovery to identify important skills, strengths, resources, and positive behaviors that are helpful in adapting and overcoming adverse experiences and promoting wellness. The crisis intervention should be guided by the specific, individualized recovery goals in SAMHSA's recovery domains of "health, home, purpose, and community" in a respectful and strengths-based manner. Peer support and recovery support services can be an integral way to help ensure services are resiliency- and recovery-oriented. Peer support providers bring their own lived experiences and can apply their own personal knowledge to the behavioral health challenges of living a life of recovery and resilience.

--- P07 ---
Taking more than 40 mg at once, or mixing tablets with alcohol, can be dangerous. Keep tablets locked away and count them every week.

--- P08 ---
[Crisis Services Should Be Responsive to Individuals' Wholistic Needs] Crisis services providers should have awareness of the needs, available community resources, and what constitutes effective care for diverse populations, including Service Members, Veterans and their families, minoritized communities, people impacted by geographic isolation, and LGB populations. CO-OCCURRING MEDICAL CONDITIONS: Providers should ensure services are accessible to individuals with co-occurring medical conditions. INTELLECTUAL AND DEVELOPMENTAL DISABILITIES (I/DD), BRAIN INJURY, AND NEUROCOGNITIVE DISORDERS: Crisis teams should be equipped with communication tools like Picture Exchange Communication Systems (PECS) or other forms of Augmentative and Alternative Communication (AAC), and soothing kits to engage individuals with I/DD. HOUSING AND OTHER SOCIAL DRIVERS OF HEALTH (SDOH): Unstable housing is a stressor both contributing to crisis events and complicating resolution of crisis events. Assessment of SDOH is critical at every step of a crisis service encounter.

--- P09 ---
[Address stress of the carers (English only in source)] Acknowledge that it is stressful to care for people with MNS conditions, but tell the carer that it is important that they continue to do so. Even when this is difficult, carers need to respect the dignity of the people they care for and involve them in making decisions about their own lives as much as possible. Ask the carers about worries and anxiety, practical challenges, ability to carry out other daily activities, physical fatigue, social support available, and psychological well-being. Address the carers' needs by giving information, linking them with community services, discussing respite care, performing problem-solving counselling and teaching stress management.

--- P10 ---
It sounds like things have felt very heavy lately. Would you be willing to tell me a little about what has been weighing on you most? You don't have to find the right words.

--- P11 ---
[Crisis Services Should Be Person-Centered, Family-Focused, and Provide the Right Level of Care at the Right Time] Crisis services should be strength-based, person-centered, resilience- and recovery-oriented, and responsive to those in need. The coordinated crisis services that SAMHSA envisions allow people and their families, caregivers, and other supporters (when appropriate) to determine what is a crisis and when services are needed to the greatest extent possible. As with the use of 911 and EDs, the help seekers themselves can define the crisis. Communities should have an array of crisis services at different levels of care, including emergency access for people who have the highest acuity of need and services in less restrictive and more inclusive environments for those with less acute needs. Services across the crisis continuum should also be transparent about policies impacting data and privacy, as well as policies with respect to initiation of non-consensual interventions, and have established policies for the receipt and response to grievances. Policies should emphasize at all levels the importance and limits of confidentiality and privacy in accordance with the Health Insurance Portability and Accountability Act, Confidentiality of Substance Use Disorder Patient Records (42 CFR Part 2), and any applicable state requirements.

--- P12 ---
[Crisis Services Should Be Evidence-Based, Evidence-Informed, and/or Reflect Best, Promising, and Emerging Practices] Services should be informed by the best available research and practice-based evidence. Services should be considered in the context of the populations served, organizational context, and the broader community in which they are provided. Provider organizations should ensure adequate resources to employ paid staff trained in evidence-based practices and to provide staff with supervision to ensure services are delivered as intended.

--- P13 ---
[Crisis Services Should Be Equitably Accessible and Responsive to the Diverse Needs of Populations] In pursuit of equity, it is necessary to acknowledge that access to behavioral health crisis care services can vary significantly for different populations. All crisis services should optimize accessibility and support underserved populations (e.g., LGB youth and adults, people who live in rural areas, people with disabilities, unhoused individuals, older adults, American Indian, Alaska Native, and Indigenous communities, and other racial and ethnic minority groups). Services should be equitably available to all populations and not discriminate based on race, color, religion, national origin, language spoken, ancestry, immigration status, housing status, insurance status, age, sexual orientation, height, weight, marital status, or physical, mental, or intellectual or developmental disability.

--- P14 ---
[Crisis Services Should Prioritize Safety] Although many crisis events do not involve life-threatening situations, crisis settings often provide care for people who are experiencing them and should be able to assess and mitigate those risks accordingly. Safety, for individuals experiencing a crisis, those providing the services, and the community as a whole is a foundational element for all crisis service settings. The focus of safety is on making sure help seekers and staff are neither physically nor emotionally hurt, through a welcoming, sensitive culture and responsiveness and with a no force first culture and mitigation of risks of iatrogenic harm. Capacity to screen, assess, and respond to the varied needs of people in crisis, including those with suicidal and/or homicidal thoughts and plans, as well as people who are at risk of medical complications and/or substance-related overdose, at risk of harm in a situation of interpersonal violence (IPV), or impacted by natural disasters, is a key to crisis system design.
Most services in the crisis continuum should incorporate evidence-based suicide specialized care, such as Cognitive Behavioral Therapy for Suicide Prevention (CBTSP), Dialectical Behavioral Therapy (DBT), the Collaborative Assessment and Management of Suicidality (CAMS), and other promising practices including suicide attempt survivor support groups.
Conducting a suicide and/or violence screening and risk assessment and developing a crisis or suicide safety plan are vital for promoting both the immediate safety and long-term stability of people seeking behavioral health crisis care. Safety planning interventions involve the development of a personalized list of coping and response strategies and sources of support that the person can use in the event of experiencing thoughts of harm to themselves or others. The safety plan development process should be collaborative with the care-seeking person and the provider and should focus on their strengths and goals. This resource details the need for a safety plan that is brief, clear, and person-centered. Safety planning can be done with any qualified crisis or health professional and should be made universally available to all individuals at high risk of or experiencing a behavioral health crisis.
The National Action Alliance for Suicide Prevention facilitated the development of evidence-based actions known as Zero Suicide or Suicide Safer Care. The following seven key elements of Zero Suicide or Suicide Safer Care are applicable to crisis care: Creating a leadership-driven, safety-oriented culture committed to dramatically reducing suicide among people under care; Training providers in evidence-based and culturally informed clinical practices; Systematically identifying and assessing suicide risk among people receiving care; Ensuring every individual has a pathway to care that is both timely and adequate to meet their needs and includes collaborative safety planning and a reduction in access to lethal means; Using effective, evidence-based treatments that directly target suicidal thoughts and behaviors; Providing continuous contact and support, especially after acute care; and Applying a data-driven quality improvement approach to inform system changes that will lead to improved patient outcomes and better care for those at risk.
Although individuals with behavioral health conditions are more likely to be a victim of crime than a perpetrator, crisis services need to be aware of how to assess for the risk of both aggression or violence and risk of victimization of an individual who has a behavioral health condition(s).

--- P15 ---
[Explore possible stressors and the availability of social support] What is your biggest worry these days?
آجکل آپ کی سب سے بڑی پریشانی کیا ہے؟
How do you deal with this worry?
آپ اس پریشانی سے کیسے نمٹ رہے ہیں؟
What are some of the things that give you comfort, strength and energy?
کونسے ایسے کام ہیں جو آپ کو ذہنی سکون اور حوصلہ دیتے ہیں؟
Who do you feel most comfortable sharing your problems with? When you are not feeling well, who do you turn to for help or advice?
آپ کس شخص کو اپنے مسئلے بتانے میں آسانی محسوس کرتے ہیں؟ جب آپ پریشان ہوتے ہیں تو آپ کس سے مشورے کرتے ہیں؟
How is your relationship with your family? In what way do your family and friends support you and in what way do you feel stressed by them?
آپ کے اپنے گھر والوں سے تعلقات کیسے ہیں؟ ان کی وجہ سے آپ کو کب حوصلہ ملتا ہے اور کب پریشانی ہوتی ہے؟

--- P16 ---
Stand-alone digital interventions based on evidence-based interventions such as cognitive behavioural therapy (CBT), dialectical behaviour therapy (DBT), problem-solving therapy (PST) and mindfulness should be considered as support for persons with suicidal thoughts. Strength of recommendation: Conditional Certainty of evidence: Low

--- P17 ---
[Explore possible suicidal thoughts and suicide attempts] Questions regarding suicide may also be perceived as offensive, but they are also essential questions in an MNS assessment. Try to ask questions in a culturally sensitive and non-judgmental way. If the person expresses hopelessness, ask further questions.
What are your hopes for the future?
آپ کو اپنا مستقبل کیسا لگتا ہے؟
Do you feel that life is worth living?
کیا آپ کو کبھی ایسا لگا ہے کہ زندگی جینے کے قابل نہیں رہی؟
Do you think about hurting yourself?
کیا آپ نے کبھی اپنے آپ کو نقصان پہنچانے کے بارے میں سوچا ہے؟
Have you made any plans to end your life?
کیا آپ نے کبھی زندگی کو ختم کرنے کے طریقے کے بارے میں سوچا ہے؟

--- P18 ---
Self-harm: Intentional self-inflicted poisoning or injury, which may or may not have a fatal intent or outcome.

--- P19 ---
[Crisis Services Should Be Developmentally Appropriate] CHILDREN AND YOUTH: Crisis services for children, youth, and their families, caregivers, and supporters should especially utilize an approach that minimizes screening-out or triage of referrals, while prioritizing a rapid face-to-face, developmentally appropriate assessment as much as possible. Crisis staff should recognize that any removal from the home is often traumatic for children and their families. EDs, inpatient, and other crisis-bedded facilities are typically a last resort, with an emphasis on maintaining the child safely at home by engaging the family, caregivers, and others' supports in a strong crisis safety plan.
OLDER ADULTS: Crisis services should be accessible for older adults aged 55 years or older. Crisis staff should be trained in the unique needs of and best practices for working effectively with older adults and conditions such as dementia, as well as with older adults experiencing abuse, neglect, and exploitation. Loneliness, social isolation, and lack of access to treatment providers are contributing factors for older adults experiencing a behavioral health crisis.

--- P20 ---
[Be aware of signs of abuse or neglect (English only in source)] Be attentive to potential signs of sexual or physical abuse (including domestic violence) in women, children and older people (e.g., unexplained bruises or injuries, excessive fear, reluctance to discuss matters when a family member is present). Be attentive to potential signs of neglect, particularly in children, people living with disability and older people. When signs of abuse or neglect are present, interview the person in a private space to ask if anything hurtful is going on. If you suspect abuse or neglect: talk immediately with your supervisor to discuss the plan of action; with the person's consent, identify community resources for protection.

--- P21 ---
[Crisis Services Should Provide Continuity of Care from Onset of Crisis Until Stability and Include Follow-Up Care and Linkage] Emergency and crisis interventions should focus on both alleviating the current crisis and lowering the risk of future episodes. Behavioral health crisis systems should implement a "no wrong door" approach where individuals are able to access crisis services regardless of how or where they initially seek help. People who are experiencing a crisis need to have continued support and resources after the initial acute crisis event. All people with current suicidal ideation or otherwise at risk of suicide should be offered follow-up services. Following up with someone after receiving crisis services has shown to aid in reductions in suicidal behaviors and reduces the likelihood that they will need crisis services again. This can include the implementation of dedicated follow-up teams resourced to: 1. Provide brief behavioral health interventions during the high-risk period immediately following a discharge from a crisis service. 2. Engage people proactively to help them connect with community-based behavioral health, health care, and social service resources that meet their needs and preferences, including culturally and linguistically appropriate services and housing services.

--- P22 ---
Safety planning type-interventions, i.e. interventions based on principles of safety planning which are multicomponent or supplemented with follow-up or support, can be considered. Strength of recommendation: Conditional Certainty of evidence: Very low

--- P23 ---
[Stress management] What are your sources of stress?
آپ کو کن معاملات سے ذہنی دباؤ محسوس ہوتا ہے؟
What can you do about these?
آپ کے خیال میں ان کا حل کیا ہے؟

--- P24 ---
Suicidal thoughts/ideation: Thoughts, ideas or ruminations about the possibility of ending one's life, ranging from thinking that one would be better off dead to formulation of elaborate plans.

--- P25 ---
[Strengthen social support] What comforts you when you are upset?
پریشانی میں آپ کو سکون کیسے ملتا ہے؟
Do you talk to anyone about your problems and what you are going through?
کس شخص سے بات کرنے سے آپ کی پریشانی کم ہوتی ہے؟
Is there any person who you feel can give you support?
مشکل وقت میں کون آپ کو سب سے زیادہ سہارا دیتا ہے؟

--- P26 ---
Ask the patient directly about suicidal thoughts, document the risk level in the chart, and refer to a specialist if the screening score is above threshold.
