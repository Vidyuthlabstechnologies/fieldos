import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { DashboardWidget } from "./DashboardWidget";

describe("DashboardWidget", () => {
  it("renders percent complete, DPR streak, and open issues", () => {
    render(
      <DashboardWidget dashboard={{ percent_tasks_complete: 50, dpr_streak_days: 3, open_issue_count: 2 }} />
    );

    expect(screen.getByText("50%")).toBeInTheDocument();
    expect(screen.getByText("3")).toBeInTheDocument();
    expect(screen.getByText("2")).toBeInTheDocument();
  });
});
