export type Emotion = 'happy' | 'sad' | 'anxious' | 'calm' | 'neutral';
export type SeverityTier = 'mild' | 'moderate' | 'severe';
export type LonelinessProfile = 'invisible' | 'ashamed' | 'withdrawn' | 'disconnected';
export type AvatarType = 'female_human' | 'male_human' | 'fox';
export type MessageRole = 'user' | 'model';

export interface UserProfile {
  severity: SeverityTier;
  profile: LonelinessProfile;
  avatar: AvatarType | string;
}

export interface ConversationTurn {
  role: MessageRole;
  content: string;
}

export interface GeminiResponse {
  reply: string;
  emotion: Emotion;
  emotion_confidence: number;
  crisis_flag: boolean;
  sentiment_score: number;
}

export interface SendMessageInput {
  message: string;
  conversationId: string;
  context: ConversationTurn[];
  userId: string;
  userProfile: UserProfile;
}

export interface SendMessageOutput extends GeminiResponse {
  conversationId: string;
}

export interface RateLimitState {
  count: number;
  windowStart: number;
}

export interface RateLimitResult {
  allowed: boolean;
  currentCount: number;
  retryAfterMs?: number;
}

export const FALLBACK_RESPONSE: GeminiResponse = {
  reply: "I'm having trouble connecting. Please try again in a moment.",
  emotion: 'neutral',
  emotion_confidence: 0,
  crisis_flag: false,
  sentiment_score: 0,
};
