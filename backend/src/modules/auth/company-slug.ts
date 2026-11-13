import { randomBytes } from 'node:crypto';

export function generateCompanySlug(name: string): string {
  const base = name.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
    .slice(0, 47).replace(/-$/g, '') || 'loja';
  return `${base}-${randomBytes(6).toString('hex')}`;
}
