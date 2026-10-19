/** Patient-safe entry point. No professional evaluation or review types. */
import type { Locale, LocalizedText, Question, QuestionType } from './types';
export const CARE_CONSENT_VERSION = 'care-consent-v1';
export interface Answer { question_id: string; type: QuestionType; value: string | string[] | boolean }
export interface Relationship { id: string; organization_id: string; patient_uid: string; psychologist_uid: string; state: 'active' | 'closed'; consent_version: string; activated_at: string; closed_at?: string; revision: number }
export interface PatientAssignment { id: string; relationship_id: string; organization_id: string; questionnaire_version_id: string; attempt_id: string; title: LocalizedText; due_at?: string; state: 'assigned' | 'in_progress' | 'submitted'; created_at: string }
export interface PatientQuestionnaire { version_id: string; schema_version: '0.5.0'; title: LocalizedText; locales: Locale[]; questions: Question[] }
export interface PatientAttempt { id: string; assignment_id: string; patient_uid: string; version_id: string; status: 'not_started' | 'in_progress'; answers: Answer[]; revision: number; server_updated_at: string }
export interface SubmitAck { attempt_id: string; assignment_id: string; submitted_at: string; status: 'submitted' }
export type PatientDetail = { assignment: PatientAssignment; questionnaire: PatientQuestionnaire; attempt: PatientAttempt } | { assignment: PatientAssignment; acknowledgement: SubmitAck };
export interface Page<T> { items: T[]; next_cursor: string | null }
export interface Connection { id: string; organization_id: string; applicant_uid: string; psychologist_uid: string; state: 'requested' | 'awaiting_demo_payment' | 'pending_psychologist_review' | 'accepted' | 'rejected' | 'withdrawn'; demo_payment_state: 'demo_pending' | 'demo_completed'; revision: number; created_at: string; updated_at: string }
