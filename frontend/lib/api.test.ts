import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./auth", () => ({
  getToken: vi.fn(),
}));

import { apiFetch } from "./api";
import { getToken } from "./auth";

describe("apiFetch", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("attaches the local session token as a bearer header", async () => {
    (getToken as any).mockReturnValue("test-token");
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ ok: true }),
    });
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch("/projects");

    const [, options] = fetchMock.mock.calls[0];
    expect(options.headers.Authorization).toBe("Bearer test-token");
  });

  it("omits the Authorization header when there is no token", async () => {
    (getToken as any).mockReturnValue(null);
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) });
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch("/projects");

    const [, options] = fetchMock.mock.calls[0];
    expect(options.headers.Authorization).toBeUndefined();
  });

  it("throws when the API responds with a non-2xx status", async () => {
    (getToken as any).mockReturnValue(null);
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: false, status: 403, text: async () => "forbidden" })
    );

    await expect(apiFetch("/projects")).rejects.toThrow("API error 403");
  });
});
