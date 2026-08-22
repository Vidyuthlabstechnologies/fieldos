import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ProjectCard } from "./ProjectCard";

describe("ProjectCard", () => {
  it("renders the project name, client, and status", () => {
    render(
      <ProjectCard
        project={{ id: "1", company_id: "c1", name: "Skyline Towers", client_name: "Acme Developers", status: "active" }}
      />
    );

    expect(screen.getByText("Skyline Towers")).toBeInTheDocument();
    expect(screen.getByText("Acme Developers")).toBeInTheDocument();
    expect(screen.getByText("active")).toBeInTheDocument();
  });

  it("links to the project detail page", () => {
    render(<ProjectCard project={{ id: "42", company_id: "c1", name: "X", client_name: null, status: "planning" }} />);
    expect(screen.getByRole("link")).toHaveAttribute("href", "/project?id=42");
  });
});
