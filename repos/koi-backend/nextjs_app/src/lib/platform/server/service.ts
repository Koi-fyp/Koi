import 'server-only';
import { createHmac, timingSafeEqual } from 'node:crypto';
import type { AccountRecord, CapabilitiesDTO, DraftDTO, DraftListDTO, ManualContent, MembershipRecord, OrganizationDTO, VerificationRecord, VersionDTO } from '../types';
import { checkManualContent, checkSchema, hash } from './contract';
import { conflict, denied, invalid, notFound, PlatformError } from './errors';
import type { PlatformStore, PlatformTransaction } from './store';

export interface Actor { uid: string; authTime: number }
export const membershipId = (uid: string, org: string) => `member_${hash([uid, org])}`;
interface Owner { uid: string; organization_id: string }
interface Receipt { uid: string; operation: string; resource: string; request_hash: string; response: unknown; created_at: string }

// Explicit serializers: future document fields cannot silently become response fields.
export const organizationDTO = (r: OrganizationDTO): OrganizationDTO => ({ id: r.id, owner_uid: r.owner_uid, name: r.name, state: r.state, created_at: r.created_at });
export const draftDTO = (r: DraftDTO): DraftDTO => ({ id: r.id, organization_id: r.organization_id, psychologist_uid: r.psychologist_uid, revision: r.revision, content: r.content, created_at: r.created_at, updated_at: r.updated_at });
export const versionDTO = (r: VersionDTO): VersionDTO => ({ id: r.id, questionnaire_id: r.questionnaire_id, organization_id: r.organization_id, psychologist_uid: r.psychologist_uid, source_revision: r.source_revision, content: r.content, content_sha256: r.content_sha256, published_at: r.published_at, schema_version: '0.5.0' });

export class PlatformService {
  constructor(protected store: PlatformStore, protected cursorSecret: string, protected now: () => Date = () => new Date()) {
    if (cursorSecret.length < 32) throw new Error('Platform cursor signing key must have at least 32 characters');
  }
  protected time() { return this.now().toISOString(); }
  protected fresh(actor: Actor) {
    const age = +this.now() / 1000 - actor.authTime;
    if (!Number.isFinite(age) || age > 300 || age < -30) throw new PlatformError(401, 'unauthenticated');
  }
  protected async authority(tx: PlatformTransaction, actor: Actor, org?: string) {
    const account = await tx.get<AccountRecord>('accounts', actor.uid);
    const verification = await tx.get<VerificationRecord>('psychologist_verifications', actor.uid);
    if (!account || account.uid !== actor.uid || account.state !== 'registered' || !verification || verification.uid !== actor.uid || verification.state !== 'verified') throw denied();
    if (!org) return { account, verification, organization: null as OrganizationDTO | null, membership: null as MembershipRecord | null };
    const organization = await tx.get<OrganizationDTO>('organizations', org);
    const membership = await tx.get<MembershipRecord>('organization_memberships', membershipId(actor.uid, org));
    if (!organization || organization.id !== org || organization.owner_uid !== actor.uid || !membership || membership.uid !== actor.uid || membership.organization_id !== org || membership.kind !== 'owner') throw notFound();
    if (organization.state !== 'active' || membership.state !== 'active') throw denied();
    return { account, verification, organization, membership };
  }
  protected key(actor: Actor, operation: string, resource: string, key: string) {
    checkSchema('Id', key);
    return `idem_${hash([actor.uid, operation, resource, key])}`;
  }
  protected async receipt<T>(tx: PlatformTransaction, id: string, actor: Actor, operation: string, resource: string, body: unknown): Promise<T | null> {
    const r = await tx.get<Receipt>('idempotency_records', id);
    if (!r) return null;
    if (r.uid !== actor.uid || r.operation !== operation || r.resource !== resource || r.request_hash !== hash(body)) throw conflict();
    return r.response as T;
  }
  protected record(tx: PlatformTransaction, id: string, actor: Actor, operation: string, resource: string, body: unknown, response: unknown, at: string, organizationId: string) {
    tx.create('idempotency_records', id, { uid: actor.uid, organization_id: organizationId, operation, resource, request_hash: hash(body), response, created_at: at });
    tx.create('audit_events', `audit_${id}`, { actor_uid: actor.uid, organization_id: organizationId, operation, resource_id: resource, occurred_at: at });
  }
  protected output<T>(schema: string, dto: T): T { checkSchema(schema, dto); return dto; }

  async capabilities(actor: Actor): Promise<CapabilitiesDTO> {
    return this.store.transaction(async tx => {
      const account = await tx.get<AccountRecord>('accounts', actor.uid);
      const verification = await tx.get<VerificationRecord>('psychologist_verifications', actor.uid);
      const owner = await tx.get<Owner>('organization_owners', actor.uid);
      const registered = account?.uid === actor.uid && account.state === 'registered';
      let professional = registered && verification?.uid === actor.uid && verification.state === 'verified';
      const organizationIds: string[] = [];
      if (owner) {
        if (owner.uid !== actor.uid) professional = false;
        else if (professional) {
          const organization = await tx.get<OrganizationDTO>('organizations', owner.organization_id);
          const member = await tx.get<MembershipRecord>('organization_memberships', membershipId(actor.uid, owner.organization_id));
          if (organization?.id === owner.organization_id && organization.owner_uid === actor.uid && organization.state === 'active'
            && member?.uid === actor.uid && member.organization_id === organization.id && member.kind === 'owner' && member.state === 'active') organizationIds.push(organization.id);
          else professional = false;
        }
      }
      const general = registered && account.general_access === true;
      const relationships = general ? await tx.query<{ id: string; organization_id: string; psychologist_uid: string }>('patient_relationships', { patient_uid: actor.uid, state: 'active' }, null, 201) : [];
      if (relationships.length > 200) throw denied();
      const availableRelationships: typeof relationships = [];
      for (const relationship of relationships) {
        try { await this.authority(tx, { uid: relationship.psychologist_uid, authTime: actor.authTime }, relationship.organization_id); availableRelationships.push(relationship); }
        catch (error) { if (!(error instanceof PlatformError && [403, 404].includes(error.status))) throw error; }
      }
      return this.output('CapabilitiesDTO', {
        contract_version: '0.5.0', uid: actor.uid, account_state: account?.uid === actor.uid ? account.state : 'unregistered',
        authorization_revision: account?.uid === actor.uid ? account.authorization_revision : 0,
        capabilities: { companion_account_sync: general, expert_directory: general, professional_workspace: !!professional, create_organization: !!professional && !owner },
        professional_organization_ids: organizationIds, active_patient_relationships: availableRelationships.map(r => ({ relationship_id: r.id, organization_id: r.organization_id, psychologist_uid: r.psychologist_uid })),
      });
    });
  }
  async createOrganization(actor: Actor, body: unknown, key: string): Promise<OrganizationDTO> {
    this.fresh(actor); checkSchema<{ name: string }>('CreateOrganizationRequest', body);
    if (!body.name.trim()) throw invalid();
    const operation = 'ensureOrganization', resource = actor.uid, receiptId = this.key(actor, operation, resource, key), at = this.time();
    return this.store.transaction(async tx => {
      await this.authority(tx, actor);
      const owner = await tx.get<Owner>('organization_owners', actor.uid);
      if (owner && owner.uid !== actor.uid) throw denied();
      if (owner) await this.authority(tx, actor, owner.organization_id);
      const old = await this.receipt<OrganizationDTO>(tx, receiptId, actor, operation, resource, body);
      const existing = owner ? await tx.get<OrganizationDTO>('organizations', owner.organization_id) : null;
      if (old) return this.output('OrganizationDTO', organizationDTO(old));
      if (owner && owner.uid !== actor.uid) throw denied();
      const id = `org_${hash(actor.uid)}`;
      const result: OrganizationDTO = existing ? organizationDTO(existing) : { id, owner_uid: actor.uid, name: body.name.trim(), state: 'active', created_at: at };
      if (!existing) {
        tx.create('organization_owners', actor.uid, { uid: actor.uid, organization_id: id });
        tx.create('organizations', id, result);
        const memberId = membershipId(actor.uid, id);
        tx.create('organization_memberships', memberId, { id: memberId, organization_id: id, uid: actor.uid, kind: 'owner', state: 'active', revision: 1, created_at: at });
      }
      this.record(tx, receiptId, actor, operation, resource, body, result, at, result.id);
      return this.output('OrganizationDTO', result);
    });
  }
  async createDraft(actor: Actor, body: unknown, key: string): Promise<DraftDTO> {
    this.fresh(actor); checkSchema<{ organization_id: string; content: ManualContent }>('CreateQuestionnaireRequest', body); checkManualContent(body.content);
    const operation = 'createQuestionnaire', resource = body.organization_id, receiptId = this.key(actor, operation, resource, key), at = this.time();
    return this.store.transaction(async tx => {
      await this.authority(tx, actor, body.organization_id);
      const old = await this.receipt<DraftDTO>(tx, receiptId, actor, operation, resource, body);
      if (old) return this.output('QuestionnaireDraftDTO', draftDTO(old));
      const result: DraftDTO = { id: `form_${hash([actor.uid, receiptId])}`, organization_id: body.organization_id, psychologist_uid: actor.uid, revision: 1, content: body.content, created_at: at, updated_at: at };
      tx.create('questionnaires', result.id, result);
      this.record(tx, receiptId, actor, operation, resource, body, result, at, result.organization_id);
      return this.output('QuestionnaireDraftDTO', result);
    });
  }
  private async scopedDraft(tx: PlatformTransaction, actor: Actor, id: string) {
    // Do not reveal resource existence to non-clinicians, even for an unknown ID.
    await this.authority(tx, actor);
    const draft = await tx.get<DraftDTO>('questionnaires', id);
    if (!draft || draft.id !== id || draft.psychologist_uid !== actor.uid) throw notFound();
    await this.authority(tx, actor, draft.organization_id);
    return draft;
  }
  async getDraft(actor: Actor, id: string): Promise<DraftDTO> {
    checkSchema('Id', id);
    return this.store.transaction(async tx => this.output('QuestionnaireDraftDTO', draftDTO(await this.scopedDraft(tx, actor, id))));
  }
  async updateDraft(actor: Actor, id: string, body: unknown, key: string): Promise<DraftDTO> {
    this.fresh(actor); checkSchema('Id', id); checkSchema<{ expected_revision: number; content: ManualContent }>('UpdateQuestionnaireRequest', body); checkManualContent(body.content);
    const operation = 'updateQuestionnaire', receiptId = this.key(actor, operation, id, key), at = this.time();
    return this.store.transaction(async tx => {
      const current = await this.scopedDraft(tx, actor, id);
      const old = await this.receipt<DraftDTO>(tx, receiptId, actor, operation, id, body);
      if (old) return this.output('QuestionnaireDraftDTO', draftDTO(old));
      if (current.revision !== body.expected_revision) throw conflict();
      const result: DraftDTO = { id: current.id, organization_id: current.organization_id, psychologist_uid: actor.uid, revision: current.revision + 1, content: body.content, created_at: current.created_at, updated_at: at };
      tx.set('questionnaires', id, result);
      this.record(tx, receiptId, actor, operation, id, body, result, at, result.organization_id);
      return this.output('QuestionnaireDraftDTO', result);
    });
  }
  async publish(actor: Actor, id: string, body: unknown, key: string): Promise<VersionDTO> {
    this.fresh(actor); checkSchema('Id', id); checkSchema<{ expected_revision: number; expected_content_sha256: string }>('PublishRequest', body);
    const operation = 'publishQuestionnaire', receiptId = this.key(actor, operation, id, key), at = this.time();
    return this.store.transaction(async tx => {
      const draft = await this.scopedDraft(tx, actor, id);
      const versionId = `version_${hash([draft.organization_id, id, body.expected_revision])}`;
      const old = await this.receipt<VersionDTO>(tx, receiptId, actor, operation, id, body);
      const existing = await tx.get<VersionDTO>('questionnaire_versions', versionId);
      if (old) return this.output('QuestionnaireVersionDTO', versionDTO(old));
      if (existing && (existing.organization_id !== draft.organization_id || existing.psychologist_uid !== actor.uid || existing.questionnaire_id !== id || existing.source_revision !== body.expected_revision)) throw notFound();
      if (existing && existing.content_sha256 !== body.expected_content_sha256) throw conflict();
      if (!existing && (draft.revision !== body.expected_revision || hash(draft.content) !== body.expected_content_sha256)) throw conflict();
      checkManualContent(existing?.content ?? draft.content);
      const result: VersionDTO = existing ? versionDTO(existing) : { id: versionId, questionnaire_id: id, organization_id: draft.organization_id, psychologist_uid: actor.uid, source_revision: draft.revision, content: draft.content, content_sha256: hash(draft.content), published_at: at, schema_version: '0.5.0' };
      if (!existing) tx.create('questionnaire_versions', versionId, result);
      this.record(tx, receiptId, actor, operation, id, body, result, at, result.organization_id);
      return this.output('QuestionnaireVersionDTO', result);
    });
  }
  async getVersion(actor: Actor, id: string): Promise<VersionDTO> {
    checkSchema('Id', id);
    return this.store.transaction(async tx => {
      await this.authority(tx, actor);
      const version = await tx.get<VersionDTO>('questionnaire_versions', id);
      if (!version || version.id !== id || version.psychologist_uid !== actor.uid) throw notFound();
      await this.authority(tx, actor, version.organization_id);
      return this.output('QuestionnaireVersionDTO', versionDTO(version));
    });
  }
  protected cursor(actor: Actor, org: string, revision: string, after: string) {
    const payload = Buffer.from(JSON.stringify({ uid: actor.uid, org, revision, after, expires: +this.now() + 900_000 })).toString('base64url');
    return payload + '.' + createHmac('sha256', this.cursorSecret).update(payload).digest('base64url');
  }
  protected cursorAfter(cursor: string, actor: Actor, org: string, revision: string): string {
    try {
      if (cursor.length > 2048) throw invalid();
      const [payload, signature, extra] = cursor.split('.');
      const expected = createHmac('sha256', this.cursorSecret).update(payload).digest();
      const actual = Buffer.from(signature ?? '', 'base64url');
      if (extra || actual.length !== expected.length || !timingSafeEqual(expected, actual)) throw invalid();
      const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
      if (decoded.uid !== actor.uid || decoded.org !== org || decoded.revision !== revision || !Number.isFinite(decoded.expires) || decoded.expires < +this.now()) throw invalid();
      checkSchema('Id', decoded.after); return decoded.after;
    } catch { throw invalid(); }
  }
  async listDrafts(actor: Actor, org: string, limit = 25, cursor?: string): Promise<DraftListDTO> {
    checkSchema('Id', org);
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw invalid();
    return this.store.transaction(async tx => {
      const a = await this.authority(tx, actor, org);
      const revision = `${a.account.authorization_revision}:${a.verification.revision}:${a.membership!.revision}`;
      const after = cursor ? this.cursorAfter(cursor, actor, org, revision) : null;
      const rows = await tx.drafts(org, actor.uid, after, limit + 1);
      if (rows.some(row => row.organization_id !== org || row.psychologist_uid !== actor.uid)) throw notFound();
      const items = rows.slice(0, limit).map(draftDTO);
      return this.output('QuestionnaireDraftListDTO', { items, next_cursor: rows.length > limit ? this.cursor(actor, org, revision, items[items.length - 1].id) : null });
    });
  }
}
