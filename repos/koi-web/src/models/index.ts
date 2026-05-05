export interface UserProfile {
  avatar?: 'female_human' | 'male_human' | 'fox';
  language: 'en' | 'ur';
  notificationTime?: string; // HH:mm
}

export interface Classification {
  primary_profile?: 'invisible' | 'ashamed' | 'withdrawn' | 'disconnected';
  secondary_profile?: string;
  severity_tier?: 'mild' | 'moderate' | 'severe';
  ucla_score?: number;
}

export interface UserStats {
  total_conversations: number;
  total_check_ins: number;
  current_streak: number;
  longest_streak: number;
  jigsaw_pieces: number;
}

export interface User {
  id: string;
  createdAt: Date;
  lastActive: Date;
  profile: UserProfile;
  classification?: Classification;
  settings: Record<string, unknown>;
  stats: UserStats;
}

export interface EmotionScores {
  text_sentiment?: number;
  audio_emotion?: number;
  video_emotion?: number;
  fused_emotion?: number;
}

export interface Message {
  id: string;
  conversationId: string;
  sender: 'user' | 'ai';
  content: string;
  timestamp: Date;
  emotion_scores?: EmotionScores;
  synced: boolean;
}

export interface MoodEntry {
  id: string;
  userId: string;
  timestamp: Date;
  mood_rating: number; // 1-5
  connection_rating: number; // 1-5
  energy_rating: number; // 1-5
  loneliness_score: number;
  notes?: string;
  synced: boolean;
}

export interface CBTSession {
  id: string;
  userId: string;
  moduleType: string;
  startedAt: Date;
  completedAt?: Date;
  quality_score?: number; // 0.0-1.0
  user_insights?: string;
  jigsaw_pieces_awarded: number;
  synced: boolean;
}

export interface Task {
  id: string;
  userId: string;
  type: 'depth_experiment' | 'social_ladder_step' | 'cbt_practice' | 'self_care';
  description: string;
  commitment_level: number; // 1-10
  createdAt: Date;
  completedAt?: Date;
  archived: boolean;
  synced: boolean;
}
