import 'server-only';
import { createHash } from 'node:crypto';
import schemas from '../../../../contracts/v0.5.2/contracts.schema.json';
import { canonicalJson } from '../canonical';
import { contentIssues } from '../content';
import type { ManualContent } from '../types';
import { invalid } from './errors';

const { validate } = require('next/dist/compiled/schema-utils3') as { validate: (schema: unknown, value: unknown) => void };
const compiled = new Map<string, unknown>();
export function checkSchema<T>(name: string, value: unknown): asserts value is T {
  if (!Object.prototype.hasOwnProperty.call(schemas.definitions, name)) throw new Error('Unknown platform schema');
  // schema-utils treats a top-level data array as multiple configurations. Wrap the
  // instance so an array cannot masquerade as an object request (or a scalar ID).
  if (!compiled.has(name)) compiled.set(name, { $schema: schemas.$schema, definitions: schemas.definitions,
    type: 'object', properties: { value: { $ref: `#/definitions/${name}` } }, required: ['value'], additionalProperties: false });
  try { validate(compiled.get(name), { value }); canonicalJson(value); } catch { throw invalid(); }
}
export const hash = (value: unknown) => createHash('sha256').update(canonicalJson(value)).digest('hex');
export function checkManualContent(value: unknown): asserts value is ManualContent {
  checkSchema<ManualContent>('CustomQuestionnaireContent', value);
  const content = value as ManualContent;
  // WEB-1 implements manual content only. AI-generated drafts remain disconnected.
  if (content.origin !== 'manual' || contentIssues(content).length || Buffer.byteLength(canonicalJson(content), 'utf8') > 400_000) throw invalid();
}
