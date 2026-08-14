import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const pushMock = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock }),
}));

vi.mock("@/lib/auth", () => ({
  login: vi.fn(),
  register: vi.fn(),
}));

import LoginPage from "./page";
import { login, register } from "@/lib/auth";

describe("LoginPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("logs in with username and password, then redirects to /projects", async () => {
    (login as any).mockResolvedValue({ token: "t", user: { id: "1", username: "eng1", name: "Eng One" } });
    render(<LoginPage />);

    fireEvent.change(screen.getByLabelText(/username/i), { target: { value: "eng1" } });
    fireEvent.change(screen.getByLabelText(/password/i), { target: { value: "password123" } });
    fireEvent.click(screen.getByRole("button", { name: /sign in/i }));

    await Promise.resolve();
    expect(login).toHaveBeenCalledWith("eng1", "password123");
    expect(pushMock).toHaveBeenCalledWith("/projects");
  });

  it("switches to register mode and creates an account", async () => {
    (register as any).mockResolvedValue({ token: "t", user: { id: "1", username: "eng2", name: "Eng Two" } });
    render(<LoginPage />);

    fireEvent.click(screen.getByRole("button", { name: /create an account/i }));
    fireEvent.change(screen.getByLabelText(/username/i), { target: { value: "eng2" } });
    fireEvent.change(screen.getByLabelText(/full name/i), { target: { value: "Eng Two" } });
    fireEvent.change(screen.getByLabelText(/password/i), { target: { value: "password123" } });
    fireEvent.click(screen.getByRole("button", { name: /create account/i }));

    await Promise.resolve();
    expect(register).toHaveBeenCalledWith("eng2", "Eng Two", "password123");
    expect(pushMock).toHaveBeenCalledWith("/projects");
  });

  it("shows an error message when login fails", async () => {
    (login as any).mockRejectedValue(new Error("Invalid username or password"));
    render(<LoginPage />);

    fireEvent.change(screen.getByLabelText(/username/i), { target: { value: "eng1" } });
    fireEvent.change(screen.getByLabelText(/password/i), { target: { value: "wrong" } });
    fireEvent.click(screen.getByRole("button", { name: /sign in/i }));

    expect(await screen.findByText(/invalid username or password/i)).toBeInTheDocument();
  });
});
