const TOKEN_KEY = 'perx_access_token';
const REFRESH_TOKEN_KEY = 'perx_refresh_token';

export type PerXUser = {
  id: string;
  email: string;
  full_name: string;
  roles: string[];
  tenant_id: string;
  is_platform_admin: boolean;
};

export type PerXSession = {
  access_token: string;
  user: PerXUser;
};

export const perxApiBaseUrl = (process.env.NEXT_PUBLIC_PERX_API_BASE_URL || 'http://localhost:8000/api/v1').replace(/\/$/, '');

export function getPerXAccessToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function clearPerXSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getPerXAccessToken();
  const headers = new Headers(options.headers);
  headers.set('Accept', 'application/json');
  if (!(options.body instanceof FormData)) {
    headers.set('Content-Type', 'application/json');
  }
  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(`${perxApiBaseUrl}${path}`, {
    ...options,
    headers,
  });
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const message = data?.detail || data?.error || `HTTP ${response.status}`;
    throw new Error(typeof message === 'string' ? message : JSON.stringify(message));
  }
  return data as T;
}

export async function loginWithPerX(username: string, password: string): Promise<PerXSession> {
  const token = await request<{ access_token: string; refresh_token: string }>('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
  localStorage.setItem(TOKEN_KEY, token.access_token);
  if (token.refresh_token) {
    localStorage.setItem(REFRESH_TOKEN_KEY, token.refresh_token);
  }
  const user = await getCurrentPerXUser();
  return { access_token: token.access_token, user };
}

export async function getCurrentPerXUser(): Promise<PerXUser> {
  return request<PerXUser>('/auth/me');
}

export async function restorePerXSession(): Promise<PerXSession | null> {
  const accessToken = getPerXAccessToken();
  if (!accessToken) return null;
  try {
    const user = await getCurrentPerXUser();
    return { access_token: accessToken, user };
  } catch {
    clearPerXSession();
    return null;
  }
}

export async function perxGet<T>(path: string): Promise<T> {
  return request<T>(path);
}

export async function perxPost<T>(path: string, body: unknown): Promise<T> {
  return request<T>(path, {
    method: 'POST',
    body: JSON.stringify(body),
  });
}
