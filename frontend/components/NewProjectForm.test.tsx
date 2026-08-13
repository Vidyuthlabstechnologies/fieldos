import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { NewProjectForm } from "./NewProjectForm";

describe("NewProjectForm", () => {
  it("calls onSubmit with the entered name and client", () => {
    const onSubmit = vi.fn();
    render(<NewProjectForm companyId="company-1" onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/project name/i), { target: { value: "Skyline Towers" } });
    fireEvent.change(screen.getByLabelText(/client/i), { target: { value: "Acme" } });
    fireEvent.click(screen.getByRole("button", { name: /create project/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      company_id: "company-1",
      name: "Skyline Towers",
      client_name: "Acme",
    });
  });
});
