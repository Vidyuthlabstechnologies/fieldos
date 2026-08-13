import Link from "next/link";

export default function HomePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4">
      <h1 className="text-3xl font-bold">FieldOS</h1>
      <Link href="/login" className="rounded bg-slate-900 px-4 py-2 text-white">
        Sign in
      </Link>
    </main>
  );
}
