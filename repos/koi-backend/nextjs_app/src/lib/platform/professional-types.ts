/** Import only from professional screens or server modules. */
import type { Answer } from './patient-types';
import type { VersionDTO } from './types';
export interface Submission { id: string; organization_id: string; relationship_id: string; assignment_id: string; attempt_id: string; patient_uid: string; questionnaire_version_id: string; answers: Answer[]; submitted_at: string }
export interface Evaluation { id: string; organization_id: string; submission_id: string; questionnaire_version_id: string; validated_scores: Array<{ scale_id: string; value: number; instrument_template_id: string; item_version: string; scoring_version: string; implementation_version: string }>; interpretation?: string; evidence: Array<{ question_id: string; answer_index: number }>; review_status: 'unreviewed' | 'reviewed'; created_at: string; provider_response_sha256?: string }
export interface Job { id: string; organization_id: string; kind: 'evaluate'; state: 'queued' | 'claimed' | 'completed' | 'failed'; created_at: string; updated_at: string; result_ref?: string; failure_code?: 'provider_unavailable' | 'invalid_output' | 'lease_expired' | 'retry_exhausted' }
export interface Review { id: string; organization_id: string; evaluation_id: string; reviewer_uid: string; revision: number; conclusion: string; feedback?: string; created_at: string }
export type ReviewDecision = 'approve' | 'reject' | 'feedback';
export interface Decision { review: Review; decision: ReviewDecision }
export interface SubmissionWorkspace { submission: Submission; questionnaire: VersionDTO; evaluation: Evaluation; job: Job; review_revision: number }
