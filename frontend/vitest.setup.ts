import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

import "@testing-library/jest-dom/vitest";

// Without this, DOM rendered by one test's `render()` call leaks into the
// next test in the same file (RTL's auto-cleanup requires either
// `test.globals: true` in vitest.config.ts or this explicit afterEach --
// neither was configured, causing "found multiple elements" failures).
afterEach(() => {
  cleanup();
});
