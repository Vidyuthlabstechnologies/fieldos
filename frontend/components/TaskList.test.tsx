import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { TaskList } from "./TaskList";

describe("TaskList", () => {
  const tasks = [
    { id: "1", project_id: "p1", title: "Pour footing", status: "todo" as const, due_date: null },
  ];

  it("renders each task's title and status", () => {
    render(<TaskList tasks={tasks} onStatusChange={vi.fn()} />);
    expect(screen.getByText("Pour footing")).toBeInTheDocument();
    expect(screen.getByDisplayValue("todo")).toBeInTheDocument();
  });

  it("calls onStatusChange when a task's status select changes", () => {
    const onStatusChange = vi.fn();
    render(<TaskList tasks={tasks} onStatusChange={onStatusChange} />);

    fireEvent.change(screen.getByDisplayValue("todo"), { target: { value: "done" } });

    expect(onStatusChange).toHaveBeenCalledWith("1", "done");
  });
});
