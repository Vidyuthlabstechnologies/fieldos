"use client";

import { useEffect, useState } from "react";

import { clearSarvamKey, getSarvamStatus, setSarvamKey } from "@/lib/api";

export default function SettingsPage() {
  const [configured, setConfigured] = useState<boolean | null>(null);
  const [apiKey, setApiKey] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  function refresh() {
    getSarvamStatus()
      .then((s) => setConfigured(s.configured))
      .catch((err) => setError(err instanceof Error ? err.message : "Failed to load settings"));
  }

  useEffect(refresh, []);

  async function handleSave() {
    if (!apiKey.trim()) return;
    setError(null);
    setMessage(null);
    setSaving(true);
    try {
      await setSarvamKey(apiKey.trim());
      setApiKey("");
      setMessage("Saved.");
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save key");
    } finally {
      setSaving(false);
    }
  }

  async function handleClear() {
    setError(null);
    setMessage(null);
    setSaving(true);
    try {
      await clearSarvamKey();
      setMessage("Removed.");
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to remove key");
    } finally {
      setSaving(false);
    }
  }

  return (
    <main className="mx-auto max-w-xl p-6">
      <h1 className="mb-1 text-2xl font-bold">Settings</h1>
      <p className="mb-6 text-sm text-slate-500">
        FieldOS runs fully offline. Voice-to-DPR is the one feature that needs the internet, and needs a Sarvam
        API key to work.
      </p>

      <section className="rounded border border-slate-200 p-4">
        <h2 className="mb-1 text-lg font-semibold">Voice-to-DPR (Sarvam)</h2>
        {configured === null ? (
          <p className="text-sm text-slate-500">Loading...</p>
        ) : (
          <p className="mb-3 text-sm">
            Status:{" "}
            <span className={configured ? "font-medium text-green-700" : "font-medium text-slate-500"}>
              {configured ? "Configured" : "Not configured"}
            </span>
          </p>
        )}

        <label className="flex flex-col gap-1 text-sm">
          {configured ? "Replace API key" : "API key"}
          <input
            type="password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder="sk_..."
            className="rounded border border-slate-300 p-2"
          />
        </label>

        <div className="mt-3 flex gap-2">
          <button
            onClick={handleSave}
            disabled={saving || !apiKey.trim()}
            type="button"
            className="rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50"
          >
            Save
          </button>
          {configured && (
            <button
              onClick={handleClear}
              disabled={saving}
              type="button"
              className="rounded border border-slate-300 px-4 py-2 text-sm disabled:opacity-50"
            >
              Remove key
            </button>
          )}
        </div>

        {message && <p className="mt-2 text-sm text-green-700">{message}</p>}
        {error && <p className="mt-2 text-sm text-red-600">{error}</p>}

        <p className="mt-3 text-xs text-slate-500">
          Get a key at{" "}
          <a href="https://dashboard.sarvam.ai/login" className="underline">
            dashboard.sarvam.ai
          </a>
          . The key is stored locally on this machine only.
        </p>
      </section>
    </main>
  );
}
