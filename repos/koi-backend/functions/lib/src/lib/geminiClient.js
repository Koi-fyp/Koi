"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GeminiClient = void 0;
const generative_ai_1 = require("@google/generative-ai");
const index_1 = require("../types/index");
const rateLimit_1 = require("./rateLimit");
const SYSTEM_PROMPT = `You are KOI, an empathetic AI companion for loneliness support. You are NOT a therapist.
For emergencies, direct users to: Umang 0311-7786264, Emergency 15/1122.
Respond with a JSON object only:
{
  "reply": "your empathetic response here (under 150 words)",
  "emotion": "happy|sad|anxious|calm|neutral",
  "emotion_confidence": 0.0-1.0,
  "crisis_flag": true/false,
  "sentiment_score": -1 to 1
}
crisis_flag MUST be true for ANY of: self-harm, suicidal ideation, hopelessness ("no reason to live/go on/keep going"), worthlessness, wanting to disappear or die, or giving up on life. When in doubt, set crisis_flag to true.`;
const STRICT_JSON_SUFFIX = '\n\nIMPORTANT: Your entire response must be valid JSON only. No markdown, no code blocks, no extra text.';
const SAFETY_SETTINGS = [
    { category: generative_ai_1.HarmCategory.HARM_CATEGORY_HARASSMENT, threshold: generative_ai_1.HarmBlockThreshold.BLOCK_ONLY_HIGH },
    { category: generative_ai_1.HarmCategory.HARM_CATEGORY_HATE_SPEECH, threshold: generative_ai_1.HarmBlockThreshold.BLOCK_ONLY_HIGH },
    { category: generative_ai_1.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT, threshold: generative_ai_1.HarmBlockThreshold.BLOCK_ONLY_HIGH },
    { category: generative_ai_1.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold: generative_ai_1.HarmBlockThreshold.BLOCK_ONLY_HIGH },
];
const VALID_EMOTIONS = ['happy', 'sad', 'anxious', 'calm', 'neutral'];
const CRISIS_KEYWORDS = [
    'no reason to keep going',
    "don't see a reason to keep going",
    'no reason to live',
    'no reason to go on',
    'want to die',
    'want to disappear',
    'end it all',
    'end my life',
    'kill myself',
    'hurt myself',
    'self-harm',
    'suicidal',
    'suicide',
    'not worth living',
    'rather be dead',
    'can\'t go on',
    'cannot go on',
    'hopeless',
    'worthless',
    'like a burden',
];
function hasCrisisLanguage(message) {
    const lower = message.toLowerCase();
    return CRISIS_KEYWORDS.some((kw) => lower.includes(kw));
}
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
function buildHistory(context) {
    return context.slice(-5).map((turn) => ({
        role: turn.role,
        parts: [{ text: turn.content }],
    }));
}
function parseGeminiJson(raw) {
    // Strip markdown code fences if present
    const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '').trim();
    const parsed = JSON.parse(cleaned);
    const reply = typeof parsed.reply === 'string' ? parsed.reply : '';
    const emotion = VALID_EMOTIONS.includes(parsed.emotion)
        ? parsed.emotion
        : 'neutral';
    const emotion_confidence = typeof parsed.emotion_confidence === 'number'
        ? Math.min(1, Math.max(0, parsed.emotion_confidence))
        : 0.5;
    const crisis_flag = parsed.crisis_flag === true;
    const sentiment_score = typeof parsed.sentiment_score === 'number'
        ? Math.min(1, Math.max(-1, parsed.sentiment_score))
        : 0;
    if (!reply)
        throw new Error('Empty reply in Gemini response');
    return { reply, emotion, emotion_confidence, crisis_flag, sentiment_score };
}
class GeminiClient {
    constructor(apiKey) {
        this._testUserId = '__test__';
        this.genAI = new generative_ai_1.GoogleGenerativeAI(apiKey);
    }
    simulateRequests(count, userId = this._testUserId) {
        (0, rateLimit_1.forceSetCount)(userId, count);
    }
    async sendMessage(message, context, userProfile, userId = this._testUserId) {
        // Rate limit check
        const limitCheck = (0, rateLimit_1.checkRateLimit)(userId);
        if (!limitCheck.allowed) {
            return {
                ...index_1.FALLBACK_RESPONSE,
                reply: `I need a short breather. Please try again in ${Math.ceil((limitCheck.retryAfterMs ?? 60000) / 1000)} seconds.`,
            };
        }
        // Queue if approaching limit
        if ((0, rateLimit_1.isApproachingLimit)(userId)) {
            const waitMs = (0, rateLimit_1.getTimeUntilWindowReset)(userId);
            if (waitMs > 0)
                await sleep(waitMs);
        }
        const result = await this._sendWithRetry(message, context, userProfile, userId, false);
        // Safety net applied after all paths (including fallback)
        if (!result.crisis_flag && hasCrisisLanguage(message)) {
            result.crisis_flag = true;
        }
        return result;
    }
    async _sendWithRetry(message, context, userProfile, userId, strictJson, attempt = 1) {
        const maxAttempts = 3;
        const backoffMs = [2000, 4000, 8000];
        try {
            const result = await this._callGemini(message, context, userProfile, strictJson);
            (0, rateLimit_1.incrementCount)(userId);
            // Safety net: keyword patterns override model under-detection
            if (!result.crisis_flag && hasCrisisLanguage(message)) {
                result.crisis_flag = true;
            }
            return result;
        }
        catch (err) {
            const isParseError = err instanceof SyntaxError || (err instanceof Error && err.message.includes('reply'));
            if (attempt < maxAttempts) {
                // On parse failure, retry once with strict JSON instruction
                if (isParseError && !strictJson) {
                    return this._sendWithRetry(message, context, userProfile, userId, true, attempt + 1);
                }
                await sleep(backoffMs[attempt - 1]);
                return this._sendWithRetry(message, context, userProfile, userId, strictJson, attempt + 1);
            }
            return { ...index_1.FALLBACK_RESPONSE };
        }
    }
    async _callGemini(message, context, userProfile, strictJson) {
        const model = this.genAI.getGenerativeModel({
            model: 'gemini-2.5-flash',
            systemInstruction: SYSTEM_PROMPT + (strictJson ? STRICT_JSON_SUFFIX : ''),
            safetySettings: SAFETY_SETTINGS,
            generationConfig: {
                temperature: 0.7,
                topP: 0.9,
                maxOutputTokens: 512,
            },
        });
        const contextNote = `[User profile: severity=${userProfile.severity}, type=${userProfile.profile}]\n`;
        const fullMessage = contextNote + message;
        const chat = model.startChat({ history: buildHistory(context) });
        const result = await chat.sendMessage(fullMessage);
        const raw = result.response.text();
        return parseGeminiJson(raw);
    }
}
exports.GeminiClient = GeminiClient;
//# sourceMappingURL=geminiClient.js.map