import type {ExampleConfig} from './ExampleTypes';

export async function resolveToken(config: ExampleConfig): Promise<string> {
  return normalizeToken(config.token);
}

function normalizeToken(value: string): string {
  const token = value.trim();
  if (!token.startsWith('v1.')) {
    throw new Error('token must start with v1.');
  }
  return token;
}
