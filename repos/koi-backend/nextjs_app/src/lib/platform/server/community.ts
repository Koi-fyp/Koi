import 'server-only';
import { LifecycleService } from './lifecycle';
import type { Actor } from './service';
import type { PlatformTransaction } from './store';
import type { Relationship } from '../patient-types';
import type { Appointment, HumanMessage, CareNotification } from '../community-types';
import { checkSchema, hash } from './contract';
import { denied, notFound, conflict, invalid, PlatformError } from './errors';
interface Profile { id: string; organization_id: string; display_name: string; bio: string; discoverable: boolean; accepting_new_patients: boolean; revision: number }
const profileDTO = (p: Profile): Profile => ({ id: p.id, organization_id: p.organization_id, display_name: p.display_name, bio: p.bio, discoverable: p.discoverable, accepting_new_patients: p.accepting_new_patients, revision: p.revision });
const expertDTO = (p: Profile) => ({ id: p.id, display_name: p.display_name, bio: p.bio, accepting_new_patients: p.accepting_new_patients });
type Notice = CareNotification & { recipient_uid: string; relationship_id: string; organization_id: string };
const messageDTO = (m: HumanMessage): HumanMessage => ({ id: m.id, relationship_id: m.relationship_id, sender_uid: m.sender_uid, body: m.body, created_at: m.created_at });
const appointmentDTO = (a: Appointment): Appointment => ({ id: a.id, relationship_id: a.relationship_id, state: a.state, revision: a.revision, updated_at: a.updated_at, ...(a.starts_at ? { starts_at: a.starts_at, ends_at: a.ends_at } : {}) });
const noticeDTO = (n: Notice): CareNotification => {
  const field = { new_message: 'message_id', appointment_change: 'appointment_id', assignment: 'assignment_id', application_state: 'connection_request_id' }[n.kind];
  return { id: n.id, event_id: n.event_id, kind: n.kind, reference: { [field]: (n.reference as any)[field] } as CareNotification['reference'], created_at: n.created_at, ...(n.read_at ? { read_at: n.read_at } : {}) };
};

export class CommunityService extends LifecycleService {
  async patientHistory(actor: Actor, id: string, limit = 25, cursor?: string) {
    checkSchema('Id', id); if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw invalid();
    return this.store.transaction(async tx => {
      const r = await tx.get<Relationship>('patient_relationships', id);
      if (!r || r.psychologist_uid !== actor.uid) throw notFound();
      await this.authority(tx, actor, r.organization_id);
      const scope = `patient-history:${id}`, revision = String(r.revision), after = cursor ? this.cursorAfter(cursor, actor, scope, revision) : null;
      const rows = await tx.query<any>('submissions', { relationship_id: id, organization_id: r.organization_id }, after, limit + 1), page = rows.slice(0, limit);
      return this.output('ProfessionalSubmissionListDTO', { items: page.map(s => ({ id: s.id, organization_id: s.organization_id, relationship_id: s.relationship_id, assignment_id: s.assignment_id, attempt_id: s.attempt_id, patient_uid: s.patient_uid, questionnaire_version_id: s.questionnaire_version_id, answers: s.answers, submitted_at: s.submitted_at })), next_cursor: rows.length > limit ? this.cursor(actor, scope, revision, page[page.length - 1].id) : null });
    });
  }
  async archive(actor: Actor, id: string, body?: unknown, key = '') {
    checkSchema('Id', id);
    if (body !== undefined) { this.fresh(actor); checkSchema('ArchivePatientRequest', body); }
    const b = body as { expected_revision: number; archived: boolean }, op = 'archivePatient', rid = body === undefined ? '' : this.key(actor, op, id, key);
    return this.store.transaction(async tx => {
      const r = await tx.get<Relationship>('patient_relationships', id);
      if (!r || r.psychologist_uid !== actor.uid) throw notFound();
      await this.authority(tx, actor, r.organization_id);
      const current = await tx.get<{ relationship_id: string; revision: number; archived: boolean }>('patient_archives', id) ?? { relationship_id: id, revision: 0, archived: false };
      const dto = { relationship_id: id, revision: current.revision, archived: current.archived };
      if (body === undefined) return this.output('PatientArchiveDTO', dto);
      const old = await this.receipt(tx, rid, actor, op, id, body); if (old) return this.output('PatientArchiveDTO', old);
      if (current.revision !== b.expected_revision || b.archived && r.state !== 'closed') throw conflict();
      const result = { relationship_id: id, revision: current.revision + 1, archived: b.archived };
      tx.set('patient_archives', id, { ...result, organization_id: r.organization_id });
      this.record(tx, rid, actor, op, id, body, result, this.time(), r.organization_id);
      return this.output('PatientArchiveDTO', result);
    });
  }
  async submissionNotices(actor: Actor, org: string, limit = 25, cursor?: string) {
    checkSchema('Id', org); if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw invalid();
    return this.store.transaction(async tx => {
      const auth = await this.authority(tx, actor, org), revision = String(auth.account.authorization_revision);
      const scope = `submission-notifications:${org}`, after = cursor ? this.cursorAfter(cursor, actor, scope, revision) : null;
      const rows = await tx.query<any>('professional_notifications', { organization_id: org, recipient_uid: actor.uid }, after, limit + 1), page = rows.slice(0, limit);
      return this.output('ProfessionalSubmissionNoticeListDTO', { items: page.map(n => ({ id: n.id, event_id: n.event_id, submission_id: n.submission_id, created_at: n.created_at })), next_cursor: rows.length > limit ? this.cursor(actor, scope, revision, page[page.length - 1].id) : null });
    });
  }
  async profile(actor: Actor, org: string, body?: unknown, key = '') {
    if (body !== undefined) { this.fresh(actor); checkSchema('UpdateProfessionalProfileRequest', body); }
    const b = body as Omit<Profile, 'id' | 'revision'> & { expected_revision: number };
    const organization = b?.organization_id ?? org; checkSchema('Id', organization);
    const op = 'updateProfessionalProfile', rid = body === undefined ? '' : this.key(actor, op, organization, key);
    return this.store.transaction(async tx => {
      await this.authority(tx, actor, organization);
      const current = await tx.get<Profile>('psychologist_profiles', actor.uid);
      if (body === undefined) { if (!current || current.organization_id !== organization) throw notFound(); return this.output('ProfessionalProfileDTO', profileDTO(current)); }
      const old = await this.receipt<Profile>(tx, rid, actor, op, organization, body);
      if (old) return this.output('ProfessionalProfileDTO', profileDTO(old));
      if ((current?.revision ?? 0) !== b.expected_revision) throw conflict();
      if (!b.display_name.trim() || !b.bio.trim()) throw invalid();
      const result: Profile = { id: actor.uid, organization_id: organization, display_name: b.display_name.trim(), bio: b.bio.trim(), discoverable: b.discoverable, accepting_new_patients: b.accepting_new_patients, revision: b.expected_revision + 1 };
      tx.set('psychologist_profiles', actor.uid, { ...result, directory_scope: 'public_profiles' });
      this.record(tx, rid, actor, op, organization, body, result, this.time(), organization);
      return this.output('ProfessionalProfileDTO', result);
    });
  }
  async experts(actor: Actor, limit = 25, cursor?: string, id?: string) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw invalid();
    return this.store.transaction(async tx => {
      const account = await this.general(tx, actor);
      const visible = async (p: Profile) => {
        if (!p.discoverable) throw notFound();
        await this.authority(tx, { uid: p.id, authTime: actor.authTime }, p.organization_id);
        return expertDTO(p);
      };
      if (id) { checkSchema('Uid', id); const p = await tx.get<Profile>('psychologist_profiles', id); if (!p || p.id !== id) throw notFound(); return this.output('ExpertDTO', await visible(p)); }
      const revision = String(account.authorization_revision), after = cursor ? this.cursorAfter(cursor, actor, 'experts', revision) : null;
      const rows = await tx.query<Profile>('psychologist_profiles', { directory_scope: 'public_profiles' }, after, limit + 1), page = rows.slice(0, limit), items = [];
      for (const p of page) { try { items.push(await visible(p)); } catch (e) { if (e instanceof PlatformError && [403, 404].includes(e.status)) continue; throw e; } }
      return this.output('ExpertListDTO', { items, next_cursor: rows.length > limit ? this.cursor(actor, 'experts', revision, page[page.length - 1].id) : null });
    });
  }
  async analytics(actor: Actor, org: string) {
    checkSchema('Id', org);
    return this.store.transaction(async tx => {
      await this.authority(tx, actor, org);
      const collect = async (collection: string) => {
        const result: any[] = []; let after: string | null = null;
        for (;;) { const rows: any[] = await tx.query(collection, { organization_id: org }, after, 200); result.push(...rows); if (rows.length < 200) return result; if (result.length >= 10000) throw new PlatformError(503, 'unavailable'); after = rows[rows.length - 1].id; }
      };
      const assignments = await collect('assignments'), submissions = await collect('submissions');
      const series = new Map<string, { questionnaire_version_id: string; scoring_version: string; enrolled: number; submitted: number; points: Array<{ date: string; submitted: number }> }>();
      for (const a of assignments) { if (!series.has(a.questionnaire_version_id)) series.set(a.questionnaire_version_id, { questionnaire_version_id: a.questionnaire_version_id, scoring_version: 'not_applicable', enrolled: 0, submitted: 0, points: [] }); series.get(a.questionnaire_version_id)!.enrolled++; }
      const ids = new Set<string>();
      for (const s of submissions) {
        if (ids.has(s.attempt_id)) continue; ids.add(s.attempt_id);
        const group = series.get(s.questionnaire_version_id); if (!group) continue;
        group.submitted++; const date = s.submitted_at.slice(0, 10), point = group.points.find(p => p.date === date);
        if (point) point.submitted++; else group.points.push({ date, submitted: 1 });
      }
      for (const group of series.values()) { group.points.sort((a, b) => a.date.localeCompare(b.date)); if (group.points.length > 200) throw new PlatformError(503, 'unavailable'); }
      if (series.size > 1000) throw new PlatformError(503, 'unavailable');
      return this.output('ProfessionalAnalyticsDTO', { organization_id: org, series: [...series.values()] });
    });
  }
  private async participant(tx: PlatformTransaction, actor: Actor, id: string) {
    checkSchema('Id', id);
    const r = await tx.get<Relationship>('patient_relationships', id);
    if (!r || r.id !== id || ![r.patient_uid, r.psychologist_uid].includes(actor.uid)) throw notFound();
    if (r.state !== 'active') throw denied();
    if (actor.uid === r.patient_uid) await this.patientRelation(tx, actor, id);
    else await this.authority(tx, actor, r.organization_id);
    return r;
  }
  private notify(tx: PlatformTransaction, r: Relationship, actor: Actor, event: string, kind: CareNotification['kind'], reference: CareNotification['reference']) {
    const recipient = actor.uid === r.patient_uid ? r.psychologist_uid : r.patient_uid;
    const id = `notice_${hash([event, recipient])}`;
    tx.create('notifications', id, { id, event_id: event, recipient_uid: recipient, relationship_id: r.id, organization_id: r.organization_id, kind, reference, created_at: this.time() });
  }
  async sendMessage(actor: Actor, body: unknown, key: string) {
    this.fresh(actor); checkSchema<{ relationship_id: string; body: string }>('CreateMessageRequest', body);
    if (!body.body.trim()) throw invalid();
    const op = 'createHumanMessage', rid = this.key(actor, op, body.relationship_id, key);
    return this.store.transaction(async tx => {
      const r = await this.participant(tx, actor, body.relationship_id);
      const old = await this.receipt<HumanMessage>(tx, rid, actor, op, r.id, body);
      if (old) return this.output('HumanMessageDTO', messageDTO(old));
      const m: HumanMessage = { id: `message_${hash(rid)}`, relationship_id: r.id, sender_uid: actor.uid, body: body.body, created_at: this.time() };
      tx.create('messages', m.id, { ...m, organization_id: r.organization_id });
      this.notify(tx, r, actor, m.id, 'new_message', { message_id: m.id });
      this.record(tx, rid, actor, op, r.id, body, m, this.time(), r.organization_id);
      return this.output('HumanMessageDTO', m);
    });
  }
  async appointment(actor: Actor, body: unknown, key: string, id?: string) {
    this.fresh(actor);
    checkSchema(id ? 'TransitionAppointmentRequest' : 'CreateAppointmentRequest', body);
    const b = body as { relationship_id: string; expected_revision: number; to_state: Appointment['state']; starts_at?: string; ends_at?: string };
    const op = id ? 'transitionAppointment' : 'createAppointment', resource = id ?? b.relationship_id, rid = this.key(actor, op, resource, key);
    return this.store.transaction(async tx => {
      const current = id ? await tx.get<Appointment>('appointments', id) : null;
      if (id && (!current || current.id !== id)) throw notFound();
      const r = await this.participant(tx, actor, current?.relationship_id ?? b.relationship_id);
      const old = await this.receipt<Appointment>(tx, rid, actor, op, resource, body);
      if (old) return this.output('AppointmentDTO', appointmentDTO(old));
      const professional = actor.uid === r.psychologist_uid;
      let result: Appointment;
      if (!current) {
        if (professional) throw denied();
        result = { id: `appointment_${hash(rid)}`, relationship_id: r.id, state: 'requested', revision: 1, updated_at: this.time() };
      } else {
        if (current.revision !== b.expected_revision) throw conflict();
        const from = current.state, to = b.to_state;
        const allowed = to === 'proposed' && professional && from === 'requested'
          || to === 'confirmed' && !professional && from === 'proposed'
          || to === 'completed' && professional && from === 'confirmed' && !!current.ends_at && Date.parse(current.ends_at) <= +this.now()
          || to === 'rejected' && professional && ['requested', 'proposed'].includes(from)
          || to === 'cancelled' && ['requested', 'proposed', 'confirmed'].includes(from);
        if (!allowed) throw conflict();
        if (to === 'proposed') {
          if (!b.starts_at || !b.ends_at || Date.parse(b.starts_at) <= +this.now() || Date.parse(b.ends_at) <= Date.parse(b.starts_at)) throw invalid();
        } else if (b.starts_at || b.ends_at) throw invalid();
        result = { ...appointmentDTO(current), state: to, revision: current.revision + 1, updated_at: this.time(), ...(to === 'proposed' ? { starts_at: b.starts_at, ends_at: b.ends_at } : {}) };
      }
      tx.set('appointments', result.id, { ...result, organization_id: r.organization_id });
      this.notify(tx, r, actor, `${result.id}_${result.revision}`, 'appointment_change', { appointment_id: result.id });
      this.record(tx, rid, actor, op, resource, body, result, this.time(), r.organization_id);
      return this.output('AppointmentDTO', result);
    });
  }
  async conversation(actor: Actor, id: string, kind: 'messages' | 'appointments', limit = 25, cursor?: string) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw invalid();
    return this.store.transaction(async tx => {
      const r = await this.participant(tx, actor, id), scope = `${kind}:${id}`;
      const after = cursor ? this.cursorAfter(cursor, actor, scope, String(r.revision)) : null;
      const rows = await tx.query<any>(kind, { relationship_id: id, organization_id: r.organization_id }, after, limit + 1);
      const page = rows.slice(0, limit);
      return this.output(kind === 'messages' ? 'HumanMessageListDTO' : 'AppointmentListDTO', { items: page.map(row => kind === 'messages' ? messageDTO(row) : appointmentDTO(row)), next_cursor: rows.length > limit ? this.cursor(actor, scope, String(r.revision), page[page.length - 1].id) : null });
    });
  }
  async notifications(actor: Actor, limit = 25, cursor?: string, id?: string) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw invalid();
    if (!id && !cursor) await this.deliverAssignmentNotices(actor);
    return this.store.transaction(async tx => {
      const a = await tx.get<{ state: string; authorization_revision: number }>('accounts', actor.uid);
      if (a?.state !== 'registered') throw denied();
      if (id) {
        const n = await tx.get<Notice>('notifications', id);
        if (!n || n.recipient_uid !== actor.uid) throw notFound();
        await this.noticeAccess(tx, actor, n);
        const result = { ...n, read_at: n.read_at ?? this.time() };
        tx.set('notifications', id, result);
        return this.output('NotificationDTO', noticeDTO(result));
      }
      const after = cursor ? this.cursorAfter(cursor, actor, 'notifications', String(a.authorization_revision)) : null;
      const rows = await tx.query<Notice>('notifications', { recipient_uid: actor.uid }, after, limit + 1), page = rows.slice(0, limit), items = [];
      for (const n of page) {
        // Closed relationships and suspended practices never retain communication access.
        try { await this.noticeAccess(tx, actor, n); } catch (e) { if ((e as { status?: number }).status === 403 || (e as { status?: number }).status === 404) continue; throw e; }
        items.push(noticeDTO(n));
      }
      return this.output('NotificationListDTO', { items, next_cursor: rows.length > limit ? this.cursor(actor, 'notifications', String(a.authorization_revision), page[page.length - 1].id) : null });
    });
  }
  private async noticeAccess(tx: PlatformTransaction, actor: Actor, n: Notice) {
    if (n.kind !== 'application_state') return this.participant(tx, actor, n.relationship_id);
    const r = await tx.get<{ applicant_uid: string; psychologist_uid: string; organization_id: string }>('connection_requests', (n.reference as { connection_request_id: string }).connection_request_id);
    if (!r || r.organization_id !== n.organization_id) throw notFound();
    if (r.applicant_uid === actor.uid) await this.general(tx, actor);
    else if (r.psychologist_uid === actor.uid) await this.authority(tx, actor, r.organization_id);
    else throw notFound();
  }
  private async deliverAssignmentNotices(actor: Actor) {
    // Assignment records are the durable event source. Materialize on inbox refresh,
    // avoiding >500 writes for a 200-recipient assignment transaction. No worker claim.
    let after: string | null = null;
    for (let page = 0; page < 50; page++) {
      const next: string | null = await this.store.transaction(async tx => {
        const account = await tx.get<{ state: string; general_access: boolean }>('accounts', actor.uid);
        if (account?.state !== 'registered') throw denied();
        if (!account.general_access) return null;
        const rows = await tx.query<any>('assignments', { patient_uid: actor.uid }, after, 200), pending: Notice[] = [];
        for (const a of rows) {
          const id = `notice_${hash(['assignment', a.id, actor.uid])}`, previous = await tx.get('notifications', id);
          if (previous) continue;
          try { await this.patientRelation(tx, actor, a.relationship_id); } catch (e) { if (e instanceof PlatformError && [403, 404].includes(e.status)) continue; throw e; }
          pending.push({ id, event_id: a.id, recipient_uid: actor.uid, relationship_id: a.relationship_id, organization_id: a.organization_id, kind: 'assignment', reference: { assignment_id: a.id }, created_at: a.created_at });
        }
        for (const n of pending) tx.create('notifications', n.id, n);
        return rows.length === 200 ? rows[rows.length - 1].id : null;
      });
      if (!next) return; after = next;
    }
    throw new PlatformError(503, 'unavailable');
  }
}
