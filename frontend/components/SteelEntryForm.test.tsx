import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { SteelEntryForm } from "./SteelEntryForm";

describe("SteelEntryForm", () => {
  it("submits description, bar diameter, nos, and length in feet", () => {
    const onSubmit = vi.fn();
    render(<SteelEntryForm onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/description/i), { target: { value: "C1" } });
    fireEvent.change(screen.getByLabelText(/bar dia/i), { target: { value: "25" } });
    fireEvent.change(screen.getByLabelText(/nos/i), { target: { value: "16" } });
    fireEvent.change(screen.getByLabelText(/length.*ft/i), { target: { value: "10.5" } });
    fireEvent.click(screen.getByRole("button", { name: /add entry/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      description: "C1",
      bar_dia_mm: "25",
      nos: "16",
      length_ft: "10.5",
    });
  });
});
