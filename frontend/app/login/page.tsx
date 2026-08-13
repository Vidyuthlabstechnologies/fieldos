"use client";

import { useState } from "react";

import { supabase } from "@/lib/supabaseClient";

export default function LoginPage() {
  const [phone, setPhone] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSendCode() {
    setError(null);
    const { error } = await supabase.auth.signInWithOtp({ phone });
    if (error) {
      setError(error.message);
      return;
    }
    setSent(true);
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-bold">Sign in to FieldOS</h1>
      <label className="flex flex-col gap-1 text-sm">
        Phone number
        <input
          type="tel"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          placeholder="+91XXXXXXXXXX"
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <button
        onClick={handleSendCode}
        className="rounded bg-slate-900 px-4 py-2 text-white"
        type="button"
      >
        Send code
      </button>
      {sent && <p className="text-sm text-green-600">Code sent — check your phone.</p>}
      {error && <p className="text-sm text-red-600">{error}</p>}
    </main>
  );
}
