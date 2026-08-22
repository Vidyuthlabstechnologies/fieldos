from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Query, HTTPException
from sqlalchemy.orm import Session
import json
import asyncio

from fieldos.auth import verify_token, CurrentUser
from fieldos.db import get_db
from fieldos.models import Session as SessionModel
from fieldos.models import User
from fieldos.permissions import require_project_access

router = APIRouter(tags=["realtime"])


class ConnectionManager:
    def __init__(self):
        self.project_rooms: dict[str, dict[str, WebSocket]] = {}

    async def connect(self, project_id: str, user_id: str, websocket: WebSocket):
        await websocket.accept()
        if project_id not in self.project_rooms:
            self.project_rooms[project_id] = {}
        self.project_rooms[project_id][user_id] = websocket

    def disconnect(self, project_id: str, user_id: str):
        if project_id in self.project_rooms:
            self.project_rooms[project_id].pop(user_id, None)
            if not self.project_rooms[project_id]:
                del self.project_rooms[project_id]

    async def broadcast(self, project_id: str, message: dict, exclude_user: str | None = None):
        if project_id not in self.project_rooms:
            return
        disconnected = []
        for user_id, ws in self.project_rooms[project_id].items():
            if user_id == exclude_user:
                continue
            try:
                await ws.send_text(json.dumps(message))
            except Exception:
                disconnected.append(user_id)
        for uid in disconnected:
            self.disconnect(project_id, uid)

    async def send_personal(self, project_id: str, user_id: str, message: dict):
        if project_id in self.project_rooms and user_id in self.project_rooms[project_id]:
            try:
                await self.project_rooms[project_id][user_id].send_text(json.dumps(message))
            except Exception:
                self.disconnect(project_id, user_id)


manager = ConnectionManager()


@router.websocket("/projects/{project_id}/ws")
async def project_websocket(
    websocket: WebSocket,
    project_id: str,
    token: str = Query(...),
    db: Session = Depends(get_db),
):
    # Authenticate via token query param
    session = db.get(SessionModel, token)
    if not session:
        await websocket.close(code=4001, reason="Invalid token")
        return

    from datetime import datetime, timezone
    if session.expires_at < datetime.now(timezone.utc).replace(tzinfo=None):
        await websocket.close(code=4001, reason="Token expired")
        return

    user = db.get(User, session.user_id)
    if not user:
        await websocket.close(code=4001, reason="User not found")
        return

    current_user = CurrentUser(id=user.id, username=user.username)
    try:
        require_project_access(db, project_id, current_user.id)
    except HTTPException:
        await websocket.close(code=4003, reason="Not authorized for this project")
        return

    await manager.connect(project_id, current_user.id, websocket)

    try:
        while True:
            data = await websocket.receive_text()
            try:
                message = json.loads(data)
                await manager.broadcast(project_id, {
                    "type": message.get("type", "message"),
                    "payload": message.get("payload", {}),
                    "sender": current_user.id,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                }, exclude_user=current_user.id)
            except json.JSONDecodeError:
                pass
    except WebSocketDisconnect:
        manager.disconnect(project_id, current_user.id)
    except Exception:
        manager.disconnect(project_id, current_user.id)


# Helper functions for other routers to broadcast updates
async def broadcast_task_update(project_id: str, task_data: dict, actor_id: str):
    await manager.broadcast(project_id, {
        "type": "task_update",
        "payload": task_data,
    }, exclude_user=actor_id)


async def broadcast_dpr_update(project_id: str, dpr_data: dict, actor_id: str):
    await manager.broadcast(project_id, {
        "type": "dpr_update",
        "payload": dpr_data,
    }, exclude_user=actor_id)


async def broadcast_material_update(project_id: str, material_data: dict, actor_id: str):
    await manager.broadcast(project_id, {
        "type": "material_update",
        "payload": material_data,
    }, exclude_user=actor_id)


async def broadcast_worker_update(project_id: str, worker_data: dict, actor_id: str):
    await manager.broadcast(project_id, {
        "type": "worker_update",
        "payload": worker_data,
    }, exclude_user=actor_id)


async def broadcast_equipment_update(project_id: str, equipment_data: dict, actor_id: str):
    await manager.broadcast(project_id, {
        "type": "equipment_update",
        "payload": equipment_data,
    }, exclude_user=actor_id)


async def broadcast_inspection_update(project_id: str, inspection_data: dict, actor_id: str):
    await manager.broadcast(project_id, {
        "type": "inspection_update",
        "payload": inspection_data,
    }, exclude_user=actor_id)


async def broadcast_procurement_update(project_id: str, procurement_data: dict, actor_id: str):
    await manager.broadcast(project_id, {
        "type": "procurement_update",
        "payload": procurement_data,
    }, exclude_user=actor_id)