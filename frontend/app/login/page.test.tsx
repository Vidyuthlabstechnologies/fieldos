import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/supabaseClient", () => ({
  supabase: { auth: { signInWithOtp: vi.fn().mockResolvedValue({ error: null }) } },
}));

import LoginPage from "./page";
import { supabase } from "@/lib/supabaseClient";

describe("LoginPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("sends an OTP to the entered phone number", async () => {
    render(<LoginPage />);

    fireEvent.change(screen.getByLabelText(/phone number/i), {
      target: { value: "+919876543210" },
    });
    fireEvent.click(screen.getByRole("button", { name: /send code/i }));

    expect(supabase.auth.signInWithOtp).toHaveBeenCalledWith({ phone: "+919876543210" });
    expect(await screen.findByText(/code sent/i)).toBeInTheDocument();
  });
});
