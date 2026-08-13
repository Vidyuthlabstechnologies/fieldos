import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { MeasurementEntryForm } from "./MeasurementEntryForm";

describe("MeasurementEntryForm", () => {
  it("submits description, length, width, depth, and nos", () => {
    const onSubmit = vi.fn();
    render(<MeasurementEntryForm onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/description/i), { target: { value: 'WALL(9")' } });
    fireEvent.change(screen.getByLabelText(/length/i), { target: { value: "108.25" } });
    fireEvent.change(screen.getByLabelText(/width/i), { target: { value: "0.75" } });
    fireEvent.change(screen.getByLabelText(/depth/i), { target: { value: "8.85" } });
    fireEvent.change(screen.getByLabelText(/nos/i), { target: { value: "1" } });
    fireEvent.click(screen.getByRole("button", { name: /add entry/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      description: 'WALL(9")',
      length: "108.25",
      width: "0.75",
      depth: "8.85",
      nos: "1",
      is_deduction: false,
    });
  });

  it("marks the entry as a deduction when the checkbox is checked", () => {
    const onSubmit = vi.fn();
    render(<MeasurementEntryForm onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/description/i), { target: { value: "D1" } });
    fireEvent.change(screen.getByLabelText(/nos/i), { target: { value: "1" } });
    fireEvent.click(screen.getByLabelText(/deduction/i));
    fireEvent.click(screen.getByRole("button", { name: /add entry/i }));

    expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({ is_deduction: true }));
  });
});
