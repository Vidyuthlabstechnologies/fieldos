// OpenAPI 3.1 description of the public API, served at /v1/openapi.json
// (no key needed) so Postman, Zapier's and Make's importers, and code
// generators can read it. docs/openapi.json is a copy; core_test.ts checks
// the two match (`deno task openapi` rewrites it).

const READ_RESOURCES = [
  "projects",
  "tasks",
  "issues",
  "daily_reports",
  "inspections",
  "approvals",
  "rfis",
  "submittals",
  "defects",
  "drawings",
  "drawing_revisions",
  "hold_points",
  "handover_units",
  "constraints",
  "attendance",
  "material_receipts",
  "purchase_orders",
  "expenses",
  "client_bills",
  "supplier_invoices",
  "payments_received",
];

const err = (description: string) => ({
  description,
  content: { "application/json": { schema: { $ref: "#/components/schemas/Error" } } },
});

const errors = {
  "400": err("Bad query parameter or body (`bad_request`, `bad_cursor`)"),
  "401": err("No key, or a wrong or revoked key (`invalid_key`)"),
  "404": err("Not this key's company, or no such row (`not_found`, `unknown_resource`)"),
  "429": err("Over 120 calls a minute for this key (`rate_limited`); see `retry-after`"),
};

const one = (schema: unknown) => ({
  "application/json": { schema: { type: "object", required: ["data"], properties: { data: schema } } },
});

const idParam = { name: "id", in: "path", required: true, schema: { type: "string", format: "uuid" } };

const taskCreate = {
  type: "object",
  additionalProperties: false,
  required: ["project_id", "title"],
  properties: {
    project_id: { type: "string", format: "uuid", description: "The site (a `projects` id)" },
    title: { type: "string", minLength: 1, maxLength: 300 },
    status: { type: "string", enum: ["todo", "in_progress", "done", "blocked"], default: "todo" },
    priority: { type: "string", enum: ["high", "normal", "low"], default: "normal" },
    progress: { type: "integer", minimum: 0, maximum: 100, default: 0 },
    start_date: { type: ["string", "null"], format: "date" },
    due_date: { type: ["string", "null"], format: "date" },
  },
};
const taskUpdate = {
  ...taskCreate,
  required: [],
  properties: Object.fromEntries(Object.entries(taskCreate.properties).filter(([k]) => k !== "project_id")),
  minProperties: 1,
};
const issueCreate = {
  type: "object",
  additionalProperties: false,
  required: ["project_id", "description"],
  properties: {
    project_id: { type: "string", format: "uuid" },
    description: { type: "string", minLength: 1, maxLength: 2000 },
    severity: { type: "string", enum: ["low", "medium", "high", "critical"], default: "medium" },
    status: {
      type: "string",
      enum: ["open", "in_progress", "resolved", "closed"],
      default: "open",
      description: "`resolved` or `closed` also sets `resolved_at`",
    },
  },
};
const issueUpdate = {
  ...issueCreate,
  required: [],
  properties: Object.fromEntries(Object.entries(issueCreate.properties).filter(([k]) => k !== "project_id")),
  minProperties: 1,
};

function writePaths(resource: string, create: unknown, update: unknown) {
  return {
    [`/v1/${resource}`]: {
      post: {
        operationId: `create_${resource}`,
        summary: `Create one of ${resource} (key must be able to write)`,
        tags: ["Write"],
        parameters: [{
          name: "Idempotency-Key",
          in: "header",
          required: false,
          schema: { type: "string", minLength: 1, maxLength: 100 },
          description:
            "Send the same value when retrying; within a day the first answer comes back and no second row is made.",
        }],
        requestBody: { required: true, content: { "application/json": { schema: create } } },
        responses: {
          "201": { description: "Created", content: one({ $ref: "#/components/schemas/Row" }) },
          "403": err("This key can only read (`forbidden`)"),
          "409": err("Idempotency-Key reused for a different body (`idempotency_conflict`)"),
          ...errors,
        },
      },
    },
    [`/v1/${resource}/{id}`]: {
      patch: {
        operationId: `update_${resource}`,
        summary: `Change one of ${resource} (only the fields sent)`,
        tags: ["Write"],
        parameters: [idParam],
        requestBody: { required: true, content: { "application/json": { schema: update } } },
        responses: {
          "200": { description: "Changed", content: one({ $ref: "#/components/schemas/Row" }) },
          "403": err("This key can only read (`forbidden`)"),
          ...errors,
        },
      },
    },
  };
}

const readPaths = Object.fromEntries(
  READ_RESOURCES.flatMap((r) => [
    [`/v1/${r}`, {
      get: {
        operationId: `list_${r}`,
        summary: `List ${r}, ordered by id`,
        tags: ["Read"],
        parameters: [
          { $ref: "#/components/parameters/project_id" },
          { $ref: "#/components/parameters/after" },
          { $ref: "#/components/parameters/limit" },
        ],
        responses: {
          "200": {
            description: "One page",
            content: { "application/json": { schema: { $ref: "#/components/schemas/Page" } } },
          },
          ...errors,
        },
      },
    }],
    [`/v1/${r}/{id}`, {
      get: {
        operationId: `get_${r}`,
        summary: `One of ${r}`,
        tags: ["Read"],
        parameters: [idParam],
        responses: { "200": { description: "The row", content: one({ $ref: "#/components/schemas/Row" }) }, ...errors },
      },
    }],
  ]),
);

// Merge write operations into the read paths of the same URL.
const paths: Record<string, Record<string, unknown>> = { ...readPaths };
for (
  const [p, ops] of Object.entries({
    ...writePaths("tasks", taskCreate, taskUpdate),
    ...writePaths("issues", issueCreate, issueUpdate),
  })
) {
  paths[p] = { ...(paths[p] ?? {}), ...ops };
}

export const OPENAPI = {
  openapi: "3.1.0",
  info: {
    title: "FieldOS API",
    version: "1.1.0",
    description:
      "Read a construction company's FieldOS sites and records, create and update tasks and issues, and get webhooks when anything changes. " +
      "Every key belongs to one company and sees only that company's sites. The company owner makes keys in the FieldOS app: Settings, API keys. " +
      "Guide: https://github.com/Vidyuthlabstechnologies/fieldos/blob/master/docs/OPEN_API.md",
    contact: { name: "ML Dynamic Solutions", email: "info@mldynamic.com" },
  },
  servers: [{ url: "https://qybjzrrledxzhrbamdcq.supabase.co/functions/v1/public-api" }],
  security: [{ bearer: [] }, { apiKey: [] }],
  tags: [
    { name: "Read", description: "Any key" },
    { name: "Write", description: "Keys that can write" },
    { name: "Changes", description: "Poll what changed" },
    { name: "Webhooks", description: "Get changes pushed to your URL" },
  ],
  paths: {
    "/v1": {
      get: {
        operationId: "index",
        summary: "Check the key; list what the API has",
        tags: ["Read"],
        responses: { "200": { description: "OK" }, "401": errors["401"] },
      },
    },
    ...paths,
    "/v1/changes": {
      get: {
        operationId: "list_changes",
        summary: "What changed after a sequence number",
        description:
          "Remember the last `seq`, then poll `?after=<seq>`. For `changed`, fetch `/v1/<resource>/<id>`; for `deleted`, drop it.",
        tags: ["Changes"],
        parameters: [
          { $ref: "#/components/parameters/project_id" },
          {
            name: "after",
            in: "query",
            schema: { type: "string", pattern: "^[0-9]+$" },
            description: "The last `seq` you saw",
          },
          { $ref: "#/components/parameters/limit" },
        ],
        responses: {
          "200": {
            description: "Changes in order",
            content: {
              "application/json": {
                schema: {
                  type: "object",
                  properties: {
                    data: { type: "array", items: { $ref: "#/components/schemas/Change" } },
                    next: { type: ["string", "null"] },
                  },
                },
              },
            },
          },
          ...errors,
        },
      },
    },
    "/v1/webhooks": {
      get: {
        operationId: "list_webhooks",
        summary: "The company's webhooks (key must be able to write)",
        tags: ["Webhooks"],
        responses: {
          "200": {
            description: "Webhooks",
            content: one({ type: "array", items: { $ref: "#/components/schemas/Webhook" } }),
          },
          ...errors,
        },
      },
      post: {
        operationId: "create_webhook",
        summary: "Subscribe a URL (key must be able to write)",
        description: "The answer has the signing `secret`, shown only this once.",
        tags: ["Webhooks"],
        requestBody: {
          required: true,
          content: {
            "application/json": {
              schema: {
                type: "object",
                required: ["url"],
                properties: {
                  url: { type: "string", format: "uri", pattern: "^https://", maxLength: 500 },
                  events: {
                    type: "array",
                    items: { type: "string", enum: ["*", ...READ_RESOURCES] },
                    default: ["*"],
                    description: "Resources to send, or `*` for all",
                  },
                  description: { type: "string", maxLength: 60 },
                },
              },
            },
          },
        },
        responses: {
          "201": {
            description: "Subscribed",
            content: one({
              allOf: [{ $ref: "#/components/schemas/Webhook" }, {
                type: "object",
                properties: { secret: { type: "string", pattern: "^whsec_[0-9a-f]{48}$" } },
              }],
            }),
          },
          "403": err("This key can only read (`forbidden`)"),
          ...errors,
        },
      },
    },
    "/v1/webhooks/{id}": {
      delete: {
        operationId: "delete_webhook",
        summary: "Unsubscribe (key must be able to write)",
        tags: ["Webhooks"],
        parameters: [idParam],
        responses: { "200": { description: "Deleted" }, "403": err("This key can only read"), ...errors },
      },
    },
  },
  webhooks: {
    change: {
      post: {
        summary: "A record changed or was deleted",
        description:
          "POSTed to your URL. Check `FieldOS-Signature: t=<unix seconds>,v1=<hex>`: v1 is HMAC-SHA256 of `<t>.<raw body>` with your `whsec_` secret. " +
          "Answer 2xx within 10 seconds. Failures are retried after 1, 5 and 30 minutes, then 2, 5, 10 and 24 hours (8 tries). " +
          "A webhook failing for 3 days is switched off. Deliveries can arrive out of order; use `data.seq`.",
        parameters: [
          { name: "FieldOS-Signature", in: "header", required: true, schema: { type: "string" } },
          { name: "FieldOS-Event-Id", in: "header", required: true, schema: { type: "string", format: "uuid" } },
          { name: "FieldOS-Event-Type", in: "header", required: true, schema: { type: "string" } },
        ],
        requestBody: { content: { "application/json": { schema: { $ref: "#/components/schemas/Event" } } } },
        responses: { "200": { description: "Received" } },
      },
    },
  },
  components: {
    securitySchemes: {
      bearer: { type: "http", scheme: "bearer", description: "`Authorization: Bearer fos_...`" },
      apiKey: { type: "apiKey", in: "header", name: "x-api-key" },
    },
    parameters: {
      project_id: {
        name: "project_id",
        in: "query",
        schema: { type: "string", format: "uuid" },
        description: "One site only",
      },
      after: {
        name: "after",
        in: "query",
        schema: { type: "string" },
        description: "The `next` from the previous page",
      },
      limit: { name: "limit", in: "query", schema: { type: "integer", minimum: 1, maximum: 500, default: 100 } },
    },
    schemas: {
      Error: {
        type: "object",
        required: ["error", "message"],
        properties: { error: { type: "string" }, message: { type: "string" } },
      },
      Row: {
        type: "object",
        additionalProperties: true,
        description: "The server row as the phones sync it (snake_case columns). Always has `id`.",
        properties: { id: { type: "string", format: "uuid" } },
      },
      Page: {
        type: "object",
        required: ["data", "next"],
        properties: {
          data: { type: "array", items: { $ref: "#/components/schemas/Row" } },
          next: { type: ["string", "null"], description: "Pass as `after` for the next page; null on the last" },
        },
      },
      Change: {
        type: "object",
        properties: {
          seq: { type: "integer" },
          resource: { type: "string", enum: READ_RESOURCES },
          id: { type: "string", format: "uuid" },
          op: { type: "string", enum: ["changed", "deleted"] },
          changed_at: { type: "string", format: "date-time" },
        },
      },
      Webhook: {
        type: "object",
        properties: {
          id: { type: "string", format: "uuid" },
          url: { type: "string" },
          events: { type: "array", items: { type: "string" } },
          description: { type: ["string", "null"] },
          enabled: { type: "boolean" },
          disabled_reason: { type: ["string", "null"] },
          created_at: { type: "string", format: "date-time" },
          last_success_at: { type: ["string", "null"], format: "date-time" },
          last_failure_at: { type: ["string", "null"], format: "date-time" },
        },
      },
      Event: {
        type: "object",
        required: ["id", "type", "created_at", "company_id", "data"],
        properties: {
          id: { type: "string", format: "uuid", description: "Same on every retry: use it to drop repeats" },
          type: { type: "string", examples: ["tasks.changed", "approvals.changed", "client_bills.deleted", "ping"] },
          created_at: { type: "string", format: "date-time" },
          company_id: { type: "string", format: "uuid" },
          data: {
            type: "object",
            properties: {
              resource: { type: "string" },
              id: { type: "string", format: "uuid" },
              project_id: { type: ["string", "null"], format: "uuid" },
              op: { type: "string", enum: ["changed", "deleted"] },
              seq: { type: "integer" },
              changed_at: { type: "string", format: "date-time" },
              object: {
                oneOf: [{ $ref: "#/components/schemas/Row" }, { type: "null" }],
                description: "The row as it was when queued; null when deleted",
              },
            },
          },
        },
      },
    },
  },
} as const;
