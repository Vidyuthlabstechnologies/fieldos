import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { BOQTable } from "./BOQTable";

describe("BOQTable", () => {
  it("renders each line's name, quantity, unit, and amount, plus the grand total", () => {
    render(
      <BOQTable
        boq={{
          lines: [
            {
              cost_head_id: "1",
              name: 'Brick Work - 9" Walls',
              billing_unit: "CFT",
              raw_quantity: "718.509375",
              billing_quantity: "718.509375",
              rate_per_unit: "20.00",
              amount: "14370.19",
            },
          ],
          subtotal: "14370.19",
          contractor_profit_percent: "10",
          contractor_profit_amount: "1437.02",
          grand_total: "15807.21",
        }}
      />
    );

    expect(screen.getByText('Brick Work - 9" Walls')).toBeInTheDocument();
    expect(screen.getByText(/718.509375 CFT/)).toBeInTheDocument();
    expect(screen.getAllByText("14370.19")).toHaveLength(2); // line amount + subtotal
    expect(screen.getByText("15807.21")).toBeInTheDocument();
    expect(screen.getByText(/10%/)).toBeInTheDocument();
  });

  it("shows an em dash for unpriced lines instead of a blank amount", () => {
    render(
      <BOQTable
        boq={{
          lines: [
            {
              cost_head_id: "1",
              name: "Unpriced",
              billing_unit: "SFT",
              raw_quantity: "100",
              billing_quantity: "100",
              rate_per_unit: null,
              amount: null,
            },
          ],
          subtotal: "0.00",
          contractor_profit_percent: null,
          contractor_profit_amount: "0.00",
          grand_total: "0.00",
        }}
      />
    );

    // rate and amount both render as an em dash for an unpriced line.
    expect(screen.getAllByText("—")).toHaveLength(2);
  });
});
