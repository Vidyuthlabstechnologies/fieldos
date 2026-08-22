"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";

const PROJECT_LINKS = [
  { href: "/project", label: "Dashboard", icon: "▣" },
  { href: "/project/materials", label: "Materials", icon: "▲" },
  { href: "/project/workers", label: "Labour", icon: "⚒" },
  { href: "/project/equipment", label: "Equipment", icon: "⚙" },
  { href: "/project/procurement", label: "Procurement", icon: "≡" },
  { href: "/project/documents", label: "Documents", icon: "◆" },
  { href: "/project/inspections", label: "Inspections", icon: "✓" },
  { href: "/project/estimations", label: "BOQ", icon: "≡" },
];

export function Sidebar() {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const projectId = searchParams.get("id");
  const [isOpen, setIsOpen] = useState(false);
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const checkMobile = () => setIsMobile(window.innerWidth < 768);
    checkMobile();
    window.addEventListener("resize", checkMobile);
    return () => window.removeEventListener("resize", checkMobile);
  }, []);

  useEffect(() => {
    if (isMobile) setIsOpen(false);
  }, [pathname, isMobile]);

  if (!projectId && !isMobile) {
    return (
      <aside className="fixed left-0 top-0 z-40 flex h-screen w-56 flex-col border-r border-slate-200 bg-white">
        <div className="flex h-14 items-center border-b border-slate-200 px-4">
          <Link href="/projects" className="text-lg font-bold tracking-tight text-slate-900">
            FieldOS
          </Link>
        </div>
        <nav className="flex-1 overflow-y-auto px-3 py-4">
          <Link href="/projects" className="mb-4 block rounded px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">
            ← All Projects
          </Link>
        </nav>
        <div className="border-t border-slate-200 px-4 py-3">
          <Link href="/settings" className="text-xs text-slate-500 hover:text-slate-700">
            Settings
          </Link>
        </div>
      </aside>
    );
  }

  return (
    <>
      {isMobile && (
        <div
          className={`fixed inset-0 z-30 bg-black/50 lg:hidden transition-opacity ${isOpen ? "opacity-100" : "opacity-0 pointer-events-none"}`}
          onClick={() => setIsOpen(false)}
          aria-hidden="true"
        />
      )}
      <aside
        className={`
          fixed left-0 top-0 z-40 flex h-screen flex-col border-r border-slate-200 bg-white transition-transform duration-300 ease-in-out lg:translate-x-0
          ${isMobile
            ? isOpen
              ? "w-64 translate-x-0"
              : "w-64 -translate-x-full"
            : "w-56"
          }
        `}
      >
        <div className="flex h-14 items-center border-b border-slate-200 px-4">
          <Link href="/projects" className="text-lg font-bold tracking-tight text-slate-900">
            FieldOS
          </Link>
        </div>

        <nav className="flex-1 overflow-y-auto px-3 py-4">
          <Link
            href="/projects"
            className="mb-4 block rounded px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100"
          >
            ← All Projects
          </Link>

          {projectId && (
            <>
              <p className="mb-2 px-3 text-xs font-semibold uppercase text-slate-400">
                Project
              </p>
              {PROJECT_LINKS.map((link) => (
                <Link
                  key={link.href}
                  href={`${link.href}?id=${projectId}`}
                  className="mb-1 flex items-center gap-2 rounded px-3 py-2 text-sm text-slate-700 hover:bg-slate-100"
                >
                  <span className="w-5 text-center text-xs">{link.icon}</span>
                  {link.label}
                </Link>
              ))}
            </>
          )}
        </nav>

        <div className="border-t border-slate-200 px-4 py-3">
          <Link href="/settings" className="text-xs text-slate-500 hover:text-slate-700">
            Settings
          </Link>
        </div>
      </aside>
    </>
  );
}

export function MobileMenuButton({ isOpen, onClick }: { isOpen: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      className="lg:hidden p-2 rounded text-slate-600 hover:bg-slate-100"
      onClick={onClick}
      aria-label={isOpen ? "Close menu" : "Open menu"}
      aria-expanded={isOpen}
    >
      <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        {isOpen ? (
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        ) : (
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
        )}
      </svg>
    </button>
  );
}