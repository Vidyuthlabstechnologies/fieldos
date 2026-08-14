"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { login, register } from "@/lib/auth";

export default function LoginPage() {
  const router = useRouter();
  const [mode, setMode] = useState<"login" | "register">("login");
  const [username, setUsername] = useState("");
  const [name, setName] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit() {
    setError(null);
    setSubmitting(true);
    try {
      if (mode === "login") {
        await login(username, password);
      } else {
        await register(username, name, password);
      }
      router.push("/projects");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-bold">
        {mode === "login" ? "Sign in to FieldOS" : "Create your FieldOS account"}
      </h1>

      <label className="flex flex-col gap-1 text-sm">
        Username
        <input
          type="text"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>

      {mode === "register" && (
        <label className="flex flex-col gap-1 text-sm">
          Full name
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="rounded border border-slate-300 p-2"
          />
        </label>
      )}

      <label className="flex flex-col gap-1 text-sm">
        Password
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>

      <button
        onClick={handleSubmit}
        disabled={submitting}
        className="rounded bg-slate-900 px-4 py-2 text-white disabled:opacity-50"
        type="button"
      >
        {mode === "login" ? "Sign in" : "Create account"}
      </button>

      <button
        onClick={() => {
          setError(null);
          setMode(mode === "login" ? "register" : "login");
        }}
        className="text-sm text-slate-600 underline"
        type="button"
      >
        {mode === "login" ? "New here? Create an account" : "Already have an account? Sign in"}
      </button>

      {error && <p className="text-sm text-red-600">{error}</p>}
    </main>
  );
}
