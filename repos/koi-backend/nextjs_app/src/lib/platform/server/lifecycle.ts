import 'server-only';
import { createHash, createHmac, randomBytes } from 'node:crypto';
import { PlatformService, type Actor } from './service';
import type { PlatformTransaction } from './store';
import { checkSchema, hash } from './contract';
import { conflict, denied, invalid, notFound, PlatformError } from './errors';
import type { AccountRecord, VersionDTO } from '../types';
import type { Answer, Connection, Page, PatientAssignment, PatientDetail, Relationship, SubmitAck } from '../patient-types';
import type { Decision, Evaluation, Job, Review, ReviewDecision, Submission, SubmissionWorkspace } from '../professional-types';
import { answerIssues } from '../answers';
import { CARE_CONSENT_VERSION } from '../patient-types';
import { isAiFeedbackRequest, type AiFeedbackNote } from '../ai-feedback';

interface Invitation { id: string; organization_id: string; psychologist_uid: string; intended_uid?: string; nonce: string; token_hash: string; state: 'open' | 'redeemed' | 'revoked'; expires_at: string; revision: number; redeemed_by?: string }
interface Assignment { id: string; organization_id: string; relationship_id: string; patient_uid: string; psychologist_uid: string; questionnaire_version_id: string; attempt_id: string; state: 'assigned' | 'in_progress' | 'submitted' | 'revoked'; created_at: string; due_at?: string; idempotency_key: string }
interface Attempt { id: string; assignment_id: string; patient_uid: string; organization_id: string; relationship_id: string; version_id: string; status: 'not_started' | 'in_progress' | 'submitted'; answers: Answer[]; revision: number; server_updated_at: string; submitted_at?: string; submission_id?: string }
interface RequestRecord extends Connection { consent_version: string }
const tokenHash = (token: string) => createHash('sha256').update(token).digest('hex');
export const relationshipId = (organization: string, patient: string) => `relationship_${hash([organization, patient])}`;
const pick = <T>(record: T, keys: string[]): T => Object.fromEntries(keys.filter(k => (record as any)[k] !== undefined).map(k => [k, (record as any)[k]])) as T;
const connectionDTO = (r: Connection) => pick(r, ['id', 'organization_id', 'applicant_uid', 'psychologist_uid', 'state', 'demo_payment_state', 'revision', 'created_at', 'updated_at']);
const submissionDTO = (r: Submission) => pick(r, ['id', 'organization_id', 'relationship_id', 'assignment_id', 'attempt_id', 'patient_uid', 'questionnaire_version_id', 'answers', 'submitted_at']);
const reviewDTO = (r: Review) => pick(r, ['id', 'organization_id', 'evaluation_id', 'reviewer_uid', 'revision', 'conclusion', 'feedback', 'created_at']);
const relationDTO = (r: Relationship) => pick(r, ['id', 'organization_id', 'patient_uid', 'psychologist_uid', 'state', 'consent_version', 'activated_at', 'closed_at', 'revision']);

export class LifecycleService extends PlatformService {
  protected async general(tx: PlatformTransaction, actor: Actor) {
    const a = await tx.get<AccountRecord>('accounts', actor.uid);
    if (!a || a.uid !== actor.uid || a.state !== 'registered' || !a.general_access) throw denied();
    return a;
  }
  private async rate(actor: Actor, operation: string, maximum: number) {
    const bucket = Math.floor(+this.now() / 3600000), id = hash([actor.uid, operation, bucket]);
    await this.store.transaction(async tx => {
      const old = await tx.get<{ count: number }>('platform_rate_limits', id);
      if ((old?.count ?? 0) >= maximum) throw new PlatformError(429, 'rate_limited');
      tx.set('platform_rate_limits', id, { uid: actor.uid, operation, bucket, count: (old?.count ?? 0) + 1 });
      return true;
    });
  }
  protected async patientRelation(tx: PlatformTransaction, actor: Actor, id: string) {
    await this.general(tx, actor);
    const r = await tx.get<Relationship>('patient_relationships', id);
    if (!r || r.id !== id || r.patient_uid !== actor.uid) throw notFound();
    if (r.state !== 'active') throw denied();
    // A suspended practice cannot receive patient answers.
    await this.authority(tx, { uid: r.psychologist_uid, authTime: actor.authTime }, r.organization_id);
    return r;
  }
  private bump(tx: PlatformTransaction, account: AccountRecord, org: string, receiptId: string) {
    tx.set('accounts', account.uid, { ...account, authorization_revision: account.authorization_revision + 1 });
    tx.create('access_invalidation_outbox', receiptId, { uid: account.uid, organization_id: org, authorization_revision: account.authorization_revision + 1, created_at: this.time() });
  }
  private async prepareRelationship(tx: PlatformTransaction, uid: string, org: string, psychologist: string, consent: string) {
    const account = await this.general(tx, { uid, authTime: 0 });
    const id = relationshipId(org, uid), current = await tx.get<Relationship>('patient_relationships', id);
    if (current && (current.organization_id !== org || current.patient_uid !== uid || current.psychologist_uid !== psychologist)) throw notFound();
    const active = await tx.query<Relationship>('patient_relationships', { patient_uid: uid, state: 'active' }, null, 201);
    if (current?.state !== 'active' && active.length >= 200) throw invalid();
    // A closed relationship is never reopened: old assignment references must remain revoked.
    if (current?.state === 'closed') throw conflict();
    const relationship: Relationship = current ?? { id, organization_id: org, patient_uid: uid, psychologist_uid: psychologist, consent_version: consent, state: 'active', activated_at: this.time(), revision: 1 };
    return { account, relationship, existing: !!current };
  }
  private invitationToken(nonce: string) { return createHmac('sha256', this.cursorSecret).update(`invitation-v1:${nonce}`).digest('base64url'); }
  async createInvitation(actor: Actor, body: unknown, key: string) {
    this.fresh(actor); checkSchema<{ organization_id: string; intended_uid?: string; expires_at: string }>('CreateInvitationRequest', body);
    const expiry = Date.parse(body.expires_at);
    if (expiry <= +this.now() || expiry > +this.now() + 7 * 86400000) throw invalid();
    await this.rate(actor, 'invite', 30);
    const op = 'createPatientInvitation', rid = this.key(actor, op, body.organization_id, key);
    return this.store.transaction(async tx => {
      await this.authority(tx, actor, body.organization_id);
      const old = await this.receipt<{ invitation_id: string }>(tx, rid, actor, op, body.organization_id, body);
      const previous = old ? await tx.get<Invitation>('patient_invitations', old.invitation_id) : null;
      if (old) {
        if (!previous || previous.state !== 'open' || Date.parse(previous.expires_at) <= +this.now()) throw conflict();
        const token = this.invitationToken(previous.nonce);
        if (tokenHash(token) !== previous.token_hash) throw conflict();
        return this.output('InvitationCreatedDTO', { invitation_id: previous.id, token, expires_at: previous.expires_at });
      }
      const nonce = randomBytes(32).toString('base64url'), token = this.invitationToken(nonce), id = `invite_${hash(rid)}`;
      const invitation: Invitation = { id, organization_id: body.organization_id, psychologist_uid: actor.uid, ...(body.intended_uid ? { intended_uid: body.intended_uid } : {}), nonce, token_hash: tokenHash(token), state: 'open', expires_at: body.expires_at, revision: 1 };
      tx.create('patient_invitations', id, invitation);
      tx.create('invitation_token_lookup', tokenHash(token), { invitation_id: id, organization_id: body.organization_id });
      // Never persist the bearer token in receipts, audit events or URLs.
      this.record(tx, rid, actor, op, body.organization_id, body, { invitation_id: id }, this.time(), body.organization_id);
      return this.output('InvitationCreatedDTO', { invitation_id: id, token, expires_at: body.expires_at });
    });
  }
  async revokeInvitation(actor: Actor, id: string, body: unknown, key: string) {
    this.fresh(actor); checkSchema('Id', id); checkSchema<{ expected_revision: number }>('RevokeRequest', body);
    const op = 'revokePatientInvitation', rid = this.key(actor, op, id, key);
    return this.store.transaction(async tx => {
      await this.authority(tx, actor);
      const invite = await tx.get<Invitation>('patient_invitations', id);
      if (!invite || invite.id !== id || invite.psychologist_uid !== actor.uid) throw notFound();
      await this.authority(tx, actor, invite.organization_id);
      const old = await this.receipt(tx, rid, actor, op, id, body); if (old) return old;
      if (invite.state !== 'open' || invite.revision !== body.expected_revision) throw conflict();
      const result = { id, state: 'revoked', revision: invite.revision + 1 };
      tx.set('patient_invitations', id, { ...invite, state: 'revoked', revision: result.revision });
      this.record(tx, rid, actor, op, id, body, result, this.time(), invite.organization_id);
      return this.output('RevokeAckDTO', result);
    });
  }
  async redeemInvitation(actor: Actor, token: string, body: unknown, key: string) {
    this.fresh(actor); if (!/^[A-Za-z0-9_-]{43,128}$/.test(token)) throw invalid();
    checkSchema<{ consent_version: string }>('RedeemInvitationRequest', body);
    if (body.consent_version !== CARE_CONSENT_VERSION) throw invalid();
    await this.rate(actor, 'redeem', 60);
    const digest = tokenHash(token), op = 'redeemPatientInvitation', rid = this.key(actor, op, digest, key);
    return this.store.transaction(async tx => {
      await this.general(tx, actor);
      const lookup = await tx.get<{ invitation_id: string }>('invitation_token_lookup', digest);
      const invite = lookup ? await tx.get<Invitation>('patient_invitations', lookup.invitation_id) : null;
      if (!invite || invite.id !== lookup!.invitation_id || invite.token_hash !== digest || (invite.intended_uid && invite.intended_uid !== actor.uid)) throw notFound();
      await this.authority(tx, { uid: invite.psychologist_uid, authTime: actor.authTime }, invite.organization_id);
      const old = await this.receipt<{ relationship_id: string }>(tx, rid, actor, op, digest, body);
      if (old) { await this.patientRelation(tx, actor, old.relationship_id); return this.output('RelationshipAckDTO', old); }
      if (invite.state !== 'open' || Date.parse(invite.expires_at) <= +this.now()) throw conflict();
      const plan = await this.prepareRelationship(tx, actor.uid, invite.organization_id, invite.psychologist_uid, body.consent_version);
      if (!plan.existing) { tx.create('patient_relationships', plan.relationship.id, plan.relationship); this.bump(tx, plan.account, invite.organization_id, rid); }
      tx.set('patient_invitations', invite.id, { ...invite, state: 'redeemed', redeemed_by: actor.uid, revision: invite.revision + 1 });
      const ack = { relationship_id: plan.relationship.id, organization_id: invite.organization_id, state: 'active' };
      this.record(tx, rid, actor, op, digest, body, ack, this.time(), invite.organization_id);
      return this.output('RelationshipAckDTO', ack);
    });
  }
  async closeRelationship(actor: Actor, id: string, body: unknown, key: string) {
    this.fresh(actor); checkSchema('Id', id); checkSchema<{ expected_revision: number }>('RevokeRequest', body);
    const op = 'closePatientRelationship', rid = this.key(actor, op, id, key);
    return this.store.transaction(async tx => {
      await this.authority(tx, actor);
      const r = await tx.get<Relationship>('patient_relationships', id);
      if (!r || r.id !== id || r.psychologist_uid !== actor.uid) throw notFound();
      await this.authority(tx, actor, r.organization_id);
      const old = await this.receipt(tx, rid, actor, op, id, body); if (old) return old;
      const account = await tx.get<AccountRecord>('accounts', r.patient_uid);
      if (!account || r.state !== 'active' || r.revision !== body.expected_revision) throw conflict();
      const result = { id, state: 'closed', revision: r.revision + 1 };
      tx.set('patient_relationships', id, { ...r, state: 'closed', closed_at: this.time(), revision: result.revision });
      this.bump(tx, account, r.organization_id, rid);
      this.record(tx, rid, actor, op, id, body, result, this.time(), r.organization_id);
      return this.output('RevokeAckDTO', result);
    });
  }
  async createConnection(actor: Actor, body: unknown, key: string) {
    this.fresh(actor); checkSchema<{ psychologist_uid: string; consent_version: string }>('CreateConnectionRequest', body);
    if (body.consent_version !== CARE_CONSENT_VERSION) throw invalid();
    if (body.psychologist_uid === actor.uid) throw invalid();
    await this.rate(actor, 'application', 30);
    const op = 'createConnectionRequest', rid = this.key(actor, op, body.psychologist_uid, key);
    return this.store.transaction(async tx => {
      await this.general(tx, actor);
      const owner = await tx.get<{ organization_id: string }>('organization_owners', body.psychologist_uid);
      if (!owner) throw notFound();
      await this.authority(tx, { uid: body.psychologist_uid, authTime: actor.authTime }, owner.organization_id);
      const old = await this.receipt<Connection>(tx, rid, actor, op, body.psychologist_uid, body); if (old) return this.output('ConnectionRequestDTO', connectionDTO(old));
      const profile = await tx.get<{ organization_id: string; discoverable: boolean; accepting_new_patients: boolean }>('psychologist_profiles', body.psychologist_uid);
      if (!profile || profile.organization_id !== owner.organization_id || !profile.discoverable || !profile.accepting_new_patients) throw denied();
      const relation = await tx.get<Relationship>('patient_relationships', relationshipId(owner.organization_id, actor.uid));
      if (relation) throw conflict();
      const id = `request_${hash([actor.uid, owner.organization_id])}`, existing = await tx.get<RequestRecord>('connection_requests', id);
      if (existing) {
        if (existing.consent_version !== body.consent_version) throw conflict();
        this.record(tx, rid, actor, op, body.psychologist_uid, body, connectionDTO(existing), this.time(), owner.organization_id);
        return this.output('ConnectionRequestDTO', connectionDTO(existing));
      }
      const at = this.time(), record: RequestRecord = { id, organization_id: owner.organization_id, applicant_uid: actor.uid, psychologist_uid: body.psychologist_uid, state: 'requested', demo_payment_state: 'demo_pending', revision: 1, created_at: at, updated_at: at, consent_version: body.consent_version };
      tx.create('connection_requests', id, record);
      tx.create('notifications', `notice_${hash([id, 1])}`, { id: `notice_${hash([id, 1])}`, event_id: `${id}_1`, recipient_uid: body.psychologist_uid, organization_id: owner.organization_id, kind: 'application_state', reference: { connection_request_id: id }, created_at: at });
      this.record(tx, rid, actor, op, body.psychologist_uid, body, connectionDTO(record), at, owner.organization_id);
      return this.output('ConnectionRequestDTO', connectionDTO(record));
    });
  }
  async transitionConnection(actor: Actor, id: string, body: unknown, key: string, demo = false) {
    this.fresh(actor); checkSchema('Id', id);
    checkSchema<{ expected_revision: number; to_state?: Connection['state'] }>(demo ? 'DemoPaymentRequest' : 'TransitionConnectionRequest', body);
    const op = demo ? 'completeDemoPayment' : 'transitionConnectionRequest', rid = this.key(actor, op, id, key);
    return this.store.transaction(async tx => {
      const r = await tx.get<RequestRecord>('connection_requests', id);
      if (!r || r.id !== id || (r.applicant_uid !== actor.uid && r.psychologist_uid !== actor.uid)) throw notFound();
      const applicant = r.applicant_uid === actor.uid;
      if (applicant) await this.general(tx, actor); else await this.authority(tx, actor, r.organization_id);
      const old = await this.receipt<Connection>(tx, rid, actor, op, id, body); if (old) return this.output('ConnectionRequestDTO', connectionDTO(old));
      if (r.revision !== body.expected_revision) throw conflict();
      let next = body.to_state;
      if (demo) { if (!applicant || r.state !== 'awaiting_demo_payment') throw conflict(); next = 'pending_psychologist_review'; }
      else if (next === 'withdrawn') { if (!applicant || !['requested', 'awaiting_demo_payment', 'pending_psychologist_review'].includes(r.state)) throw denied(); }
      else if (next === 'awaiting_demo_payment') { if (r.state !== 'requested') throw conflict(); }
      else if (next === 'accepted' || next === 'rejected') { if (applicant || r.state !== 'pending_psychologist_review' || r.demo_payment_state !== 'demo_completed') throw denied(); }
      else throw denied(); // Only the demo action may complete payment; it never grants patient access.
      const plan = next === 'accepted' ? await this.prepareRelationship(tx, r.applicant_uid, r.organization_id, r.psychologist_uid, r.consent_version) : null;
      const result: RequestRecord = { ...r, state: next!, revision: r.revision + 1, updated_at: this.time(), demo_payment_state: demo ? 'demo_completed' : r.demo_payment_state };
      if (plan && !plan.existing) { tx.create('patient_relationships', plan.relationship.id, plan.relationship); this.bump(tx, plan.account, r.organization_id, rid); }
      tx.set('connection_requests', id, result);
      tx.create('notifications', `notice_${hash([id, result.revision])}`, { id: `notice_${hash([id, result.revision])}`, event_id: `${id}_${result.revision}`, recipient_uid: applicant ? r.psychologist_uid : r.applicant_uid, organization_id: r.organization_id, kind: 'application_state', reference: { connection_request_id: id }, created_at: this.time() });
      if (demo) tx.create('demo_payments', `demo_${id}`, { id: `demo_${id}`, connection_request_id: id, organization_id: r.organization_id, applicant_uid: r.applicant_uid, state: 'demo_completed', created_at: this.time() });
      this.record(tx, rid, actor, op, id, body, connectionDTO(result), this.time(), r.organization_id);
      return this.output('ConnectionRequestDTO', connectionDTO(result));
    });
  }
  async assign(actor: Actor, body: unknown, key: string) {
    this.fresh(actor); checkSchema<{ organization_id: string; questionnaire_version_id: string; target: { kind: 'selected'; relationship_ids: string[] } | { kind: 'all_active' }; due_at?: string }>('CreateAssignmentsRequest', body);
    const op = 'createAssignments', rid = this.key(actor, op, body.organization_id, key);
    return this.store.transaction(async tx => {
      await this.authority(tx, actor, body.organization_id);
      const v = await tx.get<VersionDTO>('questionnaire_versions', body.questionnaire_version_id);
      if (!v || v.id !== body.questionnaire_version_id || v.organization_id !== body.organization_id || v.psychologist_uid !== actor.uid) throw notFound();
      const old = await this.receipt<{ resolved_relationship_ids: string[] }>(tx, rid, actor, op, body.organization_id, body);
      const ids = old?.resolved_relationship_ids ?? (body.target.kind === 'selected' ? body.target.relationship_ids : (await tx.query<Relationship>('patient_relationships', { organization_id: body.organization_id, psychologist_uid: actor.uid, state: 'active' }, null, 201)).map(r => r.id));
      if (ids.length > 200) throw invalid();
      for (const id of ids) {
        const r = await tx.get<Relationship>('patient_relationships', id);
        if (!r || r.id !== id || r.organization_id !== body.organization_id || r.psychologist_uid !== actor.uid) throw notFound();
        if (r.state !== 'active') throw denied();
        await this.general(tx, { uid: r.patient_uid, authTime: 0 });
      }
      if (old) return this.output('AssignmentBatchAckDTO', old);
      const pairs: Array<{ assignment: Assignment; attempt: Attempt }> = [];
      for (const id of ids) {
        const r = (await tx.get<Relationship>('patient_relationships', id))!;
        const aid = `assignment_${hash([rid, id])}`, tid = `attempt_${hash(aid)}`, at = this.time();
        pairs.push({ assignment: { id: aid, organization_id: body.organization_id, relationship_id: id, patient_uid: r.patient_uid, psychologist_uid: actor.uid, questionnaire_version_id: v.id, attempt_id: tid, state: 'assigned', created_at: at, idempotency_key: key, ...(body.due_at ? { due_at: body.due_at } : {}) }, attempt: { id: tid, assignment_id: aid, patient_uid: r.patient_uid, organization_id: body.organization_id, relationship_id: id, version_id: v.id, status: 'not_started', answers: [], revision: 0, server_updated_at: at } });
      }
      for (const pair of pairs) { checkSchema('AssignmentRecord', pair.assignment); checkSchema('AttemptRecord', pair.attempt); tx.create('assignments', pair.assignment.id, pair.assignment); tx.create('attempts', pair.attempt.id, pair.attempt); }
      const result = { assignment_ids: pairs.map(p => p.assignment.id), resolved_relationship_ids: ids, created_at: this.time() };
      this.record(tx, rid, actor, op, body.organization_id, body, result, this.time(), body.organization_id);
      return this.output('AssignmentBatchAckDTO', result);
    });
  }
  private assignmentDTO(a: Assignment, v: VersionDTO): PatientAssignment {
    if (a.state === 'revoked') throw denied();
    return this.output('PatientAssignmentDTO', { id: a.id, relationship_id: a.relationship_id, organization_id: a.organization_id, questionnaire_version_id: a.questionnaire_version_id, attempt_id: a.attempt_id, title: pick(v.content.title, ['en', 'ur', 'ur-Latn']), state: a.state, created_at: a.created_at, ...(a.due_at ? { due_at: a.due_at } : {}) });
  }
  private ack(a: Attempt): SubmitAck { return this.output('PatientSubmitAckDTO', { attempt_id: a.id, assignment_id: a.assignment_id, submitted_at: a.submitted_at!, status: 'submitted' }); }
  private async patientAssignment(tx: PlatformTransaction, actor: Actor, id: string) {
    await this.general(tx, actor);
    const a = await tx.get<Assignment>('assignments', id);
    if (!a || a.id !== id || a.patient_uid !== actor.uid) throw notFound();
    const r = await this.patientRelation(tx, actor, a.relationship_id);
    if (a.organization_id !== r.organization_id || a.psychologist_uid !== r.psychologist_uid || a.state === 'revoked') throw denied();
    const t = await tx.get<Attempt>('attempts', a.attempt_id), v = await tx.get<VersionDTO>('questionnaire_versions', a.questionnaire_version_id);
    if (!t || !v || v.id !== a.questionnaire_version_id || t.id !== a.attempt_id || t.assignment_id !== a.id || t.patient_uid !== actor.uid || t.organization_id !== a.organization_id || t.relationship_id !== a.relationship_id || t.version_id !== v.id || v.organization_id !== a.organization_id || v.psychologist_uid !== a.psychologist_uid) throw notFound();
    if ((t.status === 'submitted') !== (a.state === 'submitted')) throw conflict();
    return { a, t, v };
  }
  async patientDetail(actor: Actor, id: string): Promise<PatientDetail> {
    checkSchema('Id', id);
    return this.store.transaction(async tx => {
      const { a, t, v } = await this.patientAssignment(tx, actor, id), assignment = this.assignmentDTO(a, v);
      if (t.status === 'submitted') return this.output('PatientSubmittedAssignmentDTO', { assignment, acknowledgement: this.ack(t) });
      // Explicit fields and strict nested schema: unknown nested properties fail closed.
      const result = { assignment, questionnaire: { version_id: v.id, schema_version: '0.5.0' as const, title: pick(v.content.title, ['en', 'ur', 'ur-Latn']), locales: v.content.locales, questions: v.content.questions }, attempt: { id: t.id, assignment_id: t.assignment_id, patient_uid: t.patient_uid, version_id: t.version_id, status: t.status, answers: t.answers, revision: t.revision, server_updated_at: t.server_updated_at } };
      return this.output('PatientAssignmentInProgressDTO', result);
    });
  }
  async saveAttempt(actor: Actor, id: string, body: unknown, key: string, submit = false) {
    if (submit) this.fresh(actor);
    checkSchema('Id', id); checkSchema<{ expected_revision: number; answers?: Answer[] }>(submit ? 'PatientSubmitRequest' : 'AutosaveRequest', body);
    const op = submit ? 'submitPatientAttempt' : 'autosavePatientAttempt', rid = this.key(actor, op, id, key);
    return this.store.transaction(async tx => {
      await this.general(tx, actor);
      const lookup = await tx.get<Attempt>('attempts', id);
      if (!lookup || lookup.patient_uid !== actor.uid) throw notFound();
      const { a, t, v } = await this.patientAssignment(tx, actor, lookup.assignment_id);
      if (t.id !== id) throw notFound();
      const old = await this.receipt(tx, rid, actor, op, id, body);
      if (submit && t.status === 'submitted') return this.ack(t);
      if (t.status === 'submitted') throw conflict();
      if (old) return this.output('AutosaveAckDTO', old);
      if (t.revision !== body.expected_revision) throw conflict();
      const answers = submit ? t.answers : body.answers!;
      checkSchema('Answers', answers);
      if (answerIssues(v.content.questions, answers, submit).length) throw invalid();
      const at = this.time(), updated: Attempt = { ...t, answers, revision: t.revision + 1, status: submit ? 'submitted' : 'in_progress', server_updated_at: at };
      let result: unknown;
      if (submit) {
        const sid = `submission_${hash(t.id)}`, jid = `job_${hash(sid)}`, eid = `evaluation_${hash(sid)}`;
        updated.submitted_at = at; updated.submission_id = sid;
        const submission: Submission = { id: sid, organization_id: a.organization_id, relationship_id: a.relationship_id, assignment_id: a.id, attempt_id: t.id, patient_uid: actor.uid, questionnaire_version_id: v.id, answers, submitted_at: at };
        const job: Job = { id: jid, organization_id: a.organization_id, kind: 'evaluate', state: 'queued', created_at: at, updated_at: at };
        const evaluation: Evaluation = { id: eid, organization_id: a.organization_id, submission_id: sid, questionnaire_version_id: v.id, validated_scores: [], evidence: [], review_status: 'unreviewed', created_at: at };
        checkSchema('ProfessionalSubmissionDTO', submission); checkSchema('ProfessionalEvaluationDTO', evaluation);
        const jobRecord = { job, submission_id: sid, attempt_count: 0, idempotency_key: sid, revision: 1 }; checkSchema('AIJobRecord', jobRecord);
        tx.create('submissions', sid, { ...submission, psychologist_uid: a.psychologist_uid });
        tx.create('professional_notifications', `notice_${sid}`, { id: `notice_${sid}`, event_id: sid, submission_id: sid, organization_id: a.organization_id, recipient_uid: a.psychologist_uid, created_at: at });
        tx.create('ai_jobs', jid, jobRecord); tx.create('clinician_evaluations', eid, evaluation);
        result = this.ack(updated);
      } else result = this.output('AutosaveAckDTO', { attempt_id: id, revision: updated.revision, server_updated_at: at, status: 'in_progress' });
      checkSchema('AttemptRecord', updated);
      tx.set('attempts', id, updated); tx.set('assignments', a.id, { ...a, state: submit ? 'submitted' : 'in_progress' });
      this.record(tx, rid, actor, op, id, body, result, at, a.organization_id);
      return result;
    });
  }
  private async scopedSubmission(tx: PlatformTransaction, actor: Actor, id: string) {
    await this.authority(tx, actor);
    const s = await tx.get<Submission & { psychologist_uid: string }>('submissions', id);
    if (!s || s.id !== id || s.psychologist_uid !== actor.uid) throw notFound();
    await this.authority(tx, actor, s.organization_id);
    const a = await tx.get<Assignment>('assignments', s.assignment_id);
    if (!a || a.id !== s.assignment_id || a.state !== 'submitted' || a.psychologist_uid !== actor.uid || a.organization_id !== s.organization_id || a.relationship_id !== s.relationship_id || a.patient_uid !== s.patient_uid || a.questionnaire_version_id !== s.questionnaire_version_id || a.attempt_id !== s.attempt_id) throw notFound();
    return s;
  }
  async getSubmission(actor: Actor, id: string) {
    checkSchema('Id', id); return this.store.transaction(async tx => this.output('ProfessionalSubmissionDTO', submissionDTO(await this.scopedSubmission(tx, actor, id))));
  }
  private async scopedEvaluation(tx: PlatformTransaction, actor: Actor, id: string) {
    await this.authority(tx, actor);
    const e = await tx.get<Evaluation>('clinician_evaluations', id);
    if (!e || e.id !== id) throw notFound();
    const s = await this.scopedSubmission(tx, actor, e.submission_id);
    if (e.organization_id !== s.organization_id || e.questionnaire_version_id !== s.questionnaire_version_id) throw notFound();
    return e;
  }
  private evaluationDTO(e: Evaluation, reviewed: boolean): Evaluation { return this.output<Evaluation>('ProfessionalEvaluationDTO', { ...pick(e, ['id', 'organization_id', 'submission_id', 'questionnaire_version_id', 'validated_scores', 'interpretation', 'evidence', 'created_at', 'provider_response_sha256']), review_status: reviewed ? 'reviewed' : 'unreviewed' }); }
  private async reviewHead(tx: PlatformTransaction, evaluation: Evaluation) {
    const head = await tx.get<{ organization_id: string; evaluation_id: string; revision: number }>('review_heads', evaluation.id);
    if (head && (head.organization_id !== evaluation.organization_id || head.evaluation_id !== evaluation.id)) throw notFound();
    return head;
  }
  async getEvaluation(actor: Actor, id: string) {
    checkSchema('Id', id); return this.store.transaction(async tx => { const e = await this.scopedEvaluation(tx, actor, id); const h = await this.reviewHead(tx, e); return this.evaluationDTO(e, !!h?.revision); });
  }
  async workspace(actor: Actor, id: string): Promise<SubmissionWorkspace> {
    checkSchema('Id', id);
    return this.store.transaction(async tx => {
      const s = await this.scopedSubmission(tx, actor, id), e = await this.scopedEvaluation(tx, actor, `evaluation_${hash(id)}`);
      const v = await tx.get<VersionDTO>('questionnaire_versions', s.questionnaire_version_id), j = await tx.get<{ job: Job; submission_id: string }>('ai_jobs', `job_${hash(id)}`), head = await this.reviewHead(tx, e);
      if (!v || v.id !== s.questionnaire_version_id || v.organization_id !== s.organization_id || v.psychologist_uid !== actor.uid || !j || j.job.id !== `job_${hash(id)}` || j.job.kind !== 'evaluate' || j.submission_id !== id || j.job.organization_id !== s.organization_id) throw notFound();
      return this.output('SubmissionWorkspaceDTO', { submission: submissionDTO(s), questionnaire: v, evaluation: this.evaluationDTO(e, !!head?.revision), job: pick(j.job, ['id', 'organization_id', 'kind', 'state', 'created_at', 'updated_at', 'result_ref', 'failure_code']), review_revision: head?.revision ?? 0 });
    });
  }
  async createReview(actor: Actor, body: unknown, key: string, decision = false) {
    this.fresh(actor); checkSchema<{ organization_id: string; evaluation_id: string; expected_review_revision: number; conclusion: string; feedback?: string; decision?: ReviewDecision }>(decision ? 'ReviewDecisionRequest' : 'CreateReviewRequest', body);
    if (!body.conclusion.trim()) throw invalid();
    const op = decision ? 'createReviewDecision' : 'createProfessionalReview', rid = this.key(actor, op, body.evaluation_id, key);
    return this.store.transaction(async tx => {
      const e = await this.scopedEvaluation(tx, actor, body.evaluation_id);
      if (e.organization_id !== body.organization_id) throw notFound();
      const old = await this.receipt(tx, rid, actor, op, e.id, body); if (old) return old;
      const head = await this.reviewHead(tx, e);
      if ((head?.revision ?? 0) !== body.expected_review_revision) throw conflict();
      const revision = body.expected_review_revision + 1, review: Review = { id: `review_${hash([e.id, revision])}`, organization_id: e.organization_id, evaluation_id: e.id, reviewer_uid: actor.uid, revision, conclusion: body.conclusion, ...(body.feedback ? { feedback: body.feedback } : {}), created_at: this.time() };
      tx.create('review_records', review.id, { ...review, decision: body.decision ?? 'feedback' });
      tx.set('review_heads', e.id, { organization_id: e.organization_id, evaluation_id: e.id, revision });
      const result = decision ? this.output('ReviewDecisionDTO', { review, decision: body.decision }) : this.output('ReviewRecordDTO', review);
      this.record(tx, rid, actor, op, e.id, body, result, this.time(), e.organization_id);
      return result;
    });
  }
  /** One note per evaluation and psychologist in `ai_feedback_notes`; a later send returns the first note unchanged. */
  async createAiFeedback(actor: Actor, evaluationId: string, body: unknown, key: string): Promise<AiFeedbackNote> {
    this.fresh(actor); checkSchema('Id', evaluationId);
    if (!isAiFeedbackRequest(body)) throw invalid();
    const op = 'createAiFeedbackNote', rid = this.key(actor, op, evaluationId, key);
    return this.store.transaction(async tx => {
      const e = await this.scopedEvaluation(tx, actor, evaluationId);
      const old = await this.receipt<AiFeedbackNote>(tx, rid, actor, op, e.id, body); if (old) return old;
      const id = `feedback_${hash([e.id, actor.uid])}`, first = await tx.get<AiFeedbackNote & { organization_id: string }>('ai_feedback_notes', id);
      const note = (n: AiFeedbackNote): AiFeedbackNote => ({ evaluation_id: n.evaluation_id, rating: n.rating, tags: [...n.tags], ...(n.comment ? { comment: n.comment } : {}), created_at: n.created_at, psychologist_uid: n.psychologist_uid });
      if (first) return note(first);
      const created: AiFeedbackNote = { evaluation_id: e.id, rating: body.rating, tags: [...body.tags], ...(body.comment?.trim() ? { comment: body.comment.trim() } : {}), created_at: this.time(), psychologist_uid: actor.uid };
      tx.create('ai_feedback_notes', id, { ...created, organization_id: e.organization_id });
      this.record(tx, rid, actor, op, e.id, body, created, this.time(), e.organization_id);
      return note(created);
    });
  }
  async list(actor: Actor, kind: 'relationships' | 'submissions' | 'connections' | 'assignments' | 'reviews' | 'decisions', org = '', limit = 25, cursor?: string, evaluationId?: string): Promise<Page<any>> {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw invalid();
    if (org) checkSchema('Id', org); if (evaluationId) checkSchema('Id', evaluationId);
    return this.store.transaction(async tx => {
      let revision: string, filters: Record<string, string>, collection: string;
      if (kind === 'assignments') { const a = await this.general(tx, actor); revision = String(a.authorization_revision); filters = { patient_uid: actor.uid }; collection = 'assignments'; }
      else if (kind === 'connections') {
        const owner = await tx.get<{ organization_id: string }>('organization_owners', actor.uid);
        if (owner) { org = owner.organization_id; const a = await this.authority(tx, actor, org); revision = `${a.account.authorization_revision}:${a.verification.revision}:${a.membership!.revision}`; filters = { organization_id: org, psychologist_uid: actor.uid }; }
        else { const a = await this.general(tx, actor); revision = String(a.authorization_revision); filters = { applicant_uid: actor.uid }; }
        collection = 'connection_requests';
      } else {
        if (evaluationId) org = (await this.scopedEvaluation(tx, actor, evaluationId)).organization_id;
        const a = await this.authority(tx, actor, org);
        if (!org) throw invalid();
        revision = `${a.account.authorization_revision}:${a.verification.revision}:${a.membership!.revision}`;
        filters = { organization_id: org, ...(evaluationId ? { evaluation_id: evaluationId } : { psychologist_uid: actor.uid }) };
        collection = kind === 'relationships' ? 'patient_relationships' : kind === 'submissions' ? 'submissions' : 'review_records';
      }
      const scope = `${kind}:${org}:${evaluationId ?? ''}`, after = cursor ? this.cursorAfter(cursor, actor, scope, revision) : null;
      const rows = await tx.query<any>(collection, filters, after, limit + 1), items: any[] = [];
      for (const row of rows.slice(0, limit)) {
        if (kind === 'assignments') {
          try { const { a, v } = await this.patientAssignment(tx, actor, row.id); items.push(this.assignmentDTO(a, v)); }
          catch (error) { if (!(error instanceof PlatformError && [403, 404].includes(error.status))) throw error; }
        } else if (kind === 'relationships') items.push(relationDTO(row));
        else if (kind === 'connections') items.push(connectionDTO(row));
        else if (kind === 'submissions') items.push(submissionDTO(await this.scopedSubmission(tx, actor, row.id)));
        else items.push(kind === 'decisions' ? { review: reviewDTO(row), decision: row.decision ?? 'feedback' } : reviewDTO(row));
      }
      const schema = { relationships: 'PatientRelationshipListDTO', submissions: 'ProfessionalSubmissionListDTO', connections: 'ConnectionRequestListDTO', assignments: 'PatientAssignmentListDTO', reviews: 'ReviewRecordListDTO', decisions: 'ReviewDecisionListDTO' }[kind];
      return this.output(schema, { items, next_cursor: rows.length > limit ? this.cursor(actor, scope, revision, rows[limit - 1].id) : null });
    });
  }
}
