# API Reference

## Base URL

```
Development: http://localhost:8000
Production:  https://api.fieldos.example.com
```

## Authentication

All endpoints (except `/auth/*`) require:

```
Authorization: Bearer <token>
```

Get token via `POST /auth/login` or `POST /auth/register`.

## Endpoints

### Auth

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/register` | Register new user |
| POST | `/auth/login` | Login, get session token |

**Register Request:**
```json
{ "username": "engineer1", "name": "John Doe", "password": "securepass123" }
```

**Login Request:**
```json
{ "username": "engineer1", "password": "securepass123" }
```

**Response:**
```json
{
  "token": "session_token_here",
  "user": { "id": "uuid", "username": "engineer1", "name": "John Doe" }
}
```

### Companies

| Method | Path | Description |
|--------|------|-------------|
| POST | `/companies` | Create company |
| GET | `/companies` | List user's companies |
| GET | `/companies/{id}` | Get company |
| POST | `/companies/{id}/members` | Add member |
| GET | `/companies/{id}/members` | List members |

### Projects

| Method | Path | Description |
|--------|------|-------------|
| POST | `/projects` | Create project |
| GET | `/projects?company_id={id}` | List projects |
| GET | `/projects/{id}` | Get project |
| PATCH | `/projects/{id}` | Update project |
| POST | `/projects/{id}/members` | Add member |
| GET | `/projects/{id}/members` | List members |
| POST | `/projects/{id}/export` | Export project data |
| POST | `/companies/{id}/import` | Import project data |

### Tasks

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/tasks` | List tasks |
| POST | `/projects/{id}/tasks` | Create task |
| PATCH | `/projects/{id}/tasks/{task_id}` | Update status |

### DPR

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/dpr` | List entries |
| POST | `/projects/{id}/dpr` | Create entry |
| POST | `/projects/{id}/dpr/voice-draft` | Voice → draft (multipart) |
| GET | `/projects/{id}/feed` | Site feed |
| GET | `/projects/{id}/dashboard` | Dashboard metrics |

### Issues

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/issues` | List issues |
| POST | `/projects/{id}/issues` | Create issue |
| PATCH | `/projects/{id}/issues/{issue_id}/resolve` | Resolve issue (owner/PM only) |

### Materials

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/materials` | List entries |
| POST | `/projects/{id}/materials` | Create entry |
| GET | `/projects/{id}/materials/summary` | Category summary |
| POST | `/projects/{id}/materials/{entry_id}/photos` | Upload photo |
| GET | `/projects/{id}/materials/{entry_id}/photos` | List photos |

### Workers

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/workers` | List workers |
| POST | `/projects/{id}/workers` | Create worker |
| PATCH | `/projects/{id}/workers/{worker_id}` | Update worker |
| DELETE | `/projects/{id}/workers/{worker_id}` | Deactivate worker |
| GET | `/projects/{id}/attendance` | List attendance (filter: ?date=) |
| POST | `/projects/{id}/attendance` | Mark attendance (creates or updates same-day record) |
| GET | `/projects/{id}/attendance/summary` | Today's attendance + wage-cost summary |

### Estimations / BOQ

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/estimations` | List estimations |
| POST | `/projects/{id}/estimations` | Create estimation |
| GET | `/estimations/{id}/cost-heads` | List cost heads |
| POST | `/estimations/{id}/cost-heads` | Create cost head |
| POST | `/cost-heads/{id}/measurement-entries` | Add measurement |
| POST | `/cost-heads/{id}/steel-entries` | Add steel entry |
| GET | `/estimations/{id}/boq` | Get BOQ |

### Documents

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/documents` | List (filter: ?category=) |
| POST | `/projects/{id}/documents` | Upload (multipart) — auto-increments version if a document with the same name already exists |
| GET | `/projects/{id}/documents/versions/{name}` | List all versions of a document by name |

### Procurement

| Method | Path | Description |
|--------|------|-------------|
| GET | `/companies/{id}/vendors` | List vendors |
| POST | `/companies/{id}/vendors` | Create vendor |
| GET | `/projects/{id}/requisitions` | List requisitions |
| POST | `/projects/{id}/requisitions` | Create requisition |
| PATCH | `/projects/{id}/requisitions/{id}/approve` | Approve |
| GET | `/projects/{id}/rfqs` | List RFQs |
| POST | `/projects/{id}/rfqs` | Create RFQ |
| GET | `/rfqs/{id}/quotes` | List quotes |
| POST | `/rfqs/{id}/quotes` | Create quote |
| GET | `/projects/{id}/purchase-orders` | List POs |
| POST | `/projects/{id}/purchase-orders` | Create PO |
| POST | `/purchase-orders/{id}/grn` | Create GRN |
| GET | `/purchase-orders/{id}/grn` | List GRNs |

### Equipment

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/equipment` | List equipment |
| POST | `/projects/{id}/equipment` | Create equipment |
| PATCH | `/projects/{id}/equipment/{id}` | Update |
| DELETE | `/projects/{id}/equipment/{id}` | Delete |
| GET | `/equipment/{id}/logs` | List logs |
| POST | `/equipment/{id}/logs` | Create log |

### Inspections

| Method | Path | Description |
|--------|------|-------------|
| GET | `/projects/{id}/inspections` | List (filter: ?status=) |
| POST | `/projects/{id}/inspections` | Create |
| PATCH | `/projects/{id}/inspections/{id}/complete` | Complete |
| GET | `/inspections/{id}/items` | List items |
| POST | `/inspections/{id}/items` | Add item |
| PATCH | `/inspections/{id}/items/{id}` | Update item |
| GET | `/inspections/{id}/photos` | List photos |
| POST | `/inspections/{id}/photos` | Upload photo |

### Real-time (WebSocket)

```
WS /projects/{id}/ws?token={session_token}
```

**Message Format:**
```json
{
  "type": "task_update|dpr_update|material_update|worker_update|equipment_update|inspection_update|procurement_update",
  "payload": {},
  "sender": "user_id",
  "timestamp": "ISO8601"
}
```

### Billing

| Method | Path | Description |
|--------|------|-------------|
| GET | `/billing/plans` | List plans |
| GET | `/billing/subscription?company_id={id}` | Get subscription |
| POST | `/billing/checkout-session` | Create checkout |
| POST | `/billing/portal-session` | Create portal |
| GET | `/billing/events?company_id={id}` | List events |
| POST | `/billing/webhook` | Stripe webhook |

### Settings

| Method | Path | Description |
|--------|------|-------------|
| GET | `/settings/sarvam` | Check config |
| POST | `/settings/sarvam` | Set API key |
| DELETE | `/settings/sarvam` | Clear key |

## Error Responses

```json
// 400 Bad Request
{ "detail": "Validation error details" }

// 401 Unauthorized
{ "detail": "Invalid or expired session" }

// 403 Forbidden
{ "detail": "Insufficient permissions" }

// 404 Not Found
{ "detail": "Resource not found" }

// 422 Unprocessable Entity
{ "detail": [{ "loc": ["field"], "msg": "error", "type": "value_error" }] }

// 500 Server Error
{ "detail": "Internal server error" }
```

## Rate Limits

None currently implemented.

## Versioning

API version in URL path: `/v1/` (future)
Current: implicit v1