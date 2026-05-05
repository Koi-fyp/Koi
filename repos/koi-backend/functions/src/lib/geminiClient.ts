import {
  GoogleGenerativeAI,
  HarmCategory,
  HarmBlockThreshold,
  type Content,
} from '@google/generative-ai';
import {
  type GeminiResponse,
  type UserProfile,
  type ConversationTurn,
  FALLBACK_RESPONSE,
  type Emotion,
} from '../types/index';
import {
  checkRateLimit,
  incrementCount,
  isApproachingLimit,
  getTimeUntilWindowReset,
  forceSetCount,
} from './rateLimit';

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

const STRICT_JSON_SUFFIX =
  '\n\nIMPORTANT: Your entire response must be valid JSON only. No markdown, no code blocks, no extra text.';

const SAFETY_SETTINGS = [
  { category: HarmCategory.HARM_CATEGORY_HARASSMENT, threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH },
  { category: HarmCategory.HARM_CATEGORY_HATE_SPEECH, threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH },
  { category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT, threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH },
  { category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH },
];

const VALID_EMOTIONS: Emotion[] = ['happy', 'sad', 'anxious', 'calm', 'neutral'];

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

function hasCrisisLanguage(message: string): boolean {
  const lower = message.toLowerCase();
  return CRISIS_KEYWORDS.some((kw) => lower.includes(kw));
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function buildHistory(context: ConversationTurn[]): Content[] {
  return context.slice(-5).map((turn) => ({
    role: turn.role,
    parts: [{ text: turn.content }],
  }));
}

function parseGeminiJson(raw: string): GeminiResponse {
  // Strip markdown code fences if present
  const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '').trim();
  const parsed = JSON.parse(cleaned) as Record<string, unknown>;

  const reply = typeof parsed.reply === 'string' ? parsed.reply : '';
  const emotion = VALID_EMOTIONS.includes(parsed.emotion as Emotion)
    ? (parsed.emotion as Emotion)
    : 'neutral';
  const emotion_confidence =
    typeof parsed.emotion_confidence === 'number'
      ? Math.min(1, Math.max(0, parsed.emotion_confidence))
      : 0.5;
  const crisis_flag = parsed.crisis_flag === true;
  const sentiment_score =
    typeof parsed.sentiment_score === 'number'
      ? Math.min(1, Math.max(-1, parsed.sentiment_score))
      : 0;

  if (!reply) throw new Error('Empty reply in Gemini response');

  return { reply, emotion, emotion_confidence, crisis_flag, sentiment_score };
}

export class GeminiClient {
  private readonly genAI: GoogleGenerativeAI;
  private readonly _testUserId = '__test__';

  constructor(apiKey: string) {
    this.genAI = new GoogleGenerativeAI(apiKey);
  }

  simulateRequests(count: number, userId: string = this._testUserId): void {
    forceSetCount(userId, count);
  }

  async sendMessage(
    message: string,
    context: ConversationTurn[],
    userProfile: UserProfile,
    userId: string = this._testUserId,
  ): Promise<GeminiResponse> {
    // Rate limit check
    const limitCheck = checkRateLimit(userId);
    if (!limitCheck.allowed) {
      return {
        ...FALLBACK_RESPONSE,
        reply: `I need a short breather. Please try again in ${Math.ceil((limitCheck.retryAfterMs ?? 60000) / 1000)} seconds.`,
      };
    }

    // Queue if approaching limit
    if (isApproachingLimit(userId)) {
      const waitMs = getTimeUntilWindowReset(userId);
      if (waitMs > 0) await sleep(waitMs);
    }

    const result = await this._sendWithRetry(message, context, userProfile, userId, false);
    // Safety net applied after all paths (including fallback)
    if (!result.crisis_flag && hasCrisisLanguage(message)) {
      result.crisis_flag = true;
    }
    return result;
  }

  private async _sendWithRetry(
    message: string,
    context: ConversationTurn[],
    userProfile: UserProfile,
    userId: string,
    strictJson: boolean,
    attempt = 1,
  ): Promise<GeminiResponse> {
    const maxAttempts = 3;
    const backoffMs = [2000, 4000, 8000];

    try {
      const result = await this._callGemini(message, context, userProfile, strictJson);
      incrementCount(userId);
      // Safety net: keyword patterns override model under-detection
      if (!result.crisis_flag && hasCrisisLanguage(message)) {
        result.crisis_flag = true;
      }
      return result;
    } catch (err) {
      const isParseError = err instanceof SyntaxError || (err instanceof Error && err.message.includes('reply'));

      if (attempt < maxAttempts) {
        // On parse failure, retry once with strict JSON instruction
        if (isParseError && !strictJson) {
          return this._sendWithRetry(message, context, userProfile, userId, true, attempt + 1);
        }
        await sleep(backoffMs[attempt - 1]);
        return this._sendWithRetry(message, context, userProfile, userId, strictJson, attempt + 1);
      }

      return { ...FALLBACK_RESPONSE };
    }
  }

  private async _callGemini(
    message: string,
    context: ConversationTurn[],
    userProfile: UserProfile,
    strictJson: boolean,
  ): Promise<GeminiResponse> {
    const model = this.genAI.getGenerativeModel({
      model: 'gemini-1.5-flash',
      systemInstruction: SYSTEM_PROMPT + (strictJson ? STRICT_JSON_SUFFIX : ''),
      safetySettings: SAFETY_SETTINGS,
      generationConfig: {
        temperature: 0.7,
        topP: 0.9,
        maxOutputTokens: 512,
        responseMimeType: 'application/json',
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
