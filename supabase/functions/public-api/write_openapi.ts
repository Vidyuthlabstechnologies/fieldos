// deno task openapi: rewrites docs/openapi.json from openapi.ts.
import { OPENAPI } from "./openapi.ts";

await Deno.writeTextFile(
  new URL("../../../docs/openapi.json", import.meta.url),
  JSON.stringify(OPENAPI, null, 2) + "\n",
);
