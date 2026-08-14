// Local authentication -- talks to the FieldOS backend only, no cloud
// dependency. The session token is an opaque server-issued value stored in
// localStorage, sent back as a Bearer token on every API request.

const TOKEN_KEY = "fieldos_token";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000";

export type User = { id: string; username: string; name: string };
type SessionResponse = { token: string; user: User };

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(TOKEN_KEY);
}

function setToken(token: string) {
  window.localStorage.setItem(TOKEN_KEY, token);
}

export function logout() {
  window.localStorage.removeItem(TOKEN_KEY);
}

async function authRequest(path: string, body: unknown): Promise<SessionResponse> {
  const res = await fetch(`${API_BASE_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => ({}));
    throw new Error(detail.detail ?? `Request failed (${res.status})`);
  }
  const data: SessionResponse = await res.json();
  setToken(data.token);
  return data;
}

export function register(username: string, name: string, password: string) {
  return authRequest("/auth/register", { username, name, password });
}

export function login(username: string, password: string) {
  return authRequest("/auth/login", { username, password });
}
