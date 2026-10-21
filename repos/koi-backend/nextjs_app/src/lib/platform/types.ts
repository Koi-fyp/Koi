/** WEB-1 subset of the frozen 0.5.0 contracts. No evaluations or AI DTOs in this entry point. */
export type Locale = 'en' | 'ur' | 'ur-Latn';
export type LocalizedText = Partial<Record<Locale, string>>;
export type QuestionType = 'single_choice' | 'multi_choice' | 'yes_no' | 'likert' | 'short_text' | 'image_single_choice' | 'image_multi_choice';
export interface AssetReference { asset_id: string; version: number; sha256: string }
export interface Option { id: string; label: LocalizedText; asset?: AssetReference }
export interface Question {
  id: string; prompt: LocalizedText; required: boolean; type: QuestionType;
  options?: Option[]; max_length?: number; min_selections?: number; max_selections?: number;
}
export interface ManualContent {
  kind: 'custom_questionnaire'; validation_status: 'not_validated';
  title: LocalizedText; locales: Locale[]; questions: Question[]; origin: 'manual' | 'ai_drafted';
}
export interface OrganizationDTO { id: string; owner_uid: string; name: string; state: 'active' | 'suspended'; created_at: string }
export interface DraftDTO {
  id: string; organization_id: string; psychologist_uid: string; revision: number;
  content: ManualContent; created_at: string; updated_at: string;
}
export interface VersionDTO {
  id: string; questionnaire_id: string; organization_id: string; psychologist_uid: string;
  source_revision: number; content: ManualContent; content_sha256: string;
  published_at: string; schema_version: '0.5.0';
}
export interface DraftListDTO { items: DraftDTO[]; next_cursor: string | null }
export interface CapabilitiesDTO {
  contract_version: '0.5.0'; uid: string; account_state: 'unregistered' | 'registered' | 'suspended' | 'closed';
  authorization_revision: number;
  capabilities: { companion_account_sync: boolean; expert_directory: boolean; professional_workspace: boolean; create_organization: boolean };
  professional_organization_ids: string[];
  active_patient_relationships: Array<{ relationship_id: string; organization_id: string; psychologist_uid: string }>;
}
export interface AccountRecord {
  uid: string; state: 'registered' | 'suspended' | 'closed'; general_access: boolean;
  registration_method: 'restricted_seeded_verification' | 'password_email_challenge';
  registration_evidence_id: string; registered_at: string; authorization_revision: number;
}
export interface VerificationRecord {
  uid: string; state: 'pending' | 'verified' | 'rejected' | 'suspended';
  revision: number; changed_at: string; changed_by: string; audit_id: string;
}
export interface MembershipRecord {
  id: string; organization_id: string; uid: string; kind: 'owner'; state: 'active' | 'revoked'; revision: number; created_at: string;
}
