import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { CostHeadForm } from "./CostHeadForm";

describe("CostHeadForm", () => {
  it("submits name, calculation type, units, and rate", () => {
    const onSubmit = vi.fn();
    render(<CostHeadForm onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/cost head name/i), {
      target: { value: 'Brick Work - 9" Walls' },
    });
    fireEvent.change(screen.getByLabelText(/calculation type/i), { target: { value: "volume" } });
    fireEvent.change(screen.getByLabelText(/raw unit/i), { target: { value: "CFT" } });
    fireEvent.change(screen.getByLabelText(/billing unit/i), { target: { value: "CFT" } });
    fireEvent.change(screen.getByLabelText(/rate per unit/i), { target: { value: "20" } });
    fireEvent.click(screen.getByRole("button", { name: /add cost head/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      name: 'Brick Work - 9" Walls',
      calculation_type: "volume",
      raw_unit: "CFT",
      billing_unit: "CFT",
      rate_per_unit: "20",
    });
  });
});
