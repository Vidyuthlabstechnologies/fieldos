import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { DPRForm } from "./DPRForm";

describe("DPRForm", () => {
  it("submits entry date, work summary, and manpower count", () => {
    const onSubmit = vi.fn();
    render(<DPRForm onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/date/i), { target: { value: "2026-08-11" } });
    fireEvent.change(screen.getByLabelText(/work summary/i), {
      target: { value: "Poured 50 cum concrete on footing F12" },
    });
    fireEvent.change(screen.getByLabelText(/manpower/i), { target: { value: "8" } });
    fireEvent.click(screen.getByRole("button", { name: /submit dpr/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      entry_date: "2026-08-11",
      work_summary: "Poured 50 cum concrete on footing F12",
      manpower_count: 8,
    });
  });
});
