export interface ConversationMessage {
  id: string;
  speaker: 'user' | 'companion';
  text: string;
  language?: 'en' | 'ur';
}
