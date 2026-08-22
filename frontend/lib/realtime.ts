"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { getToken } from "@/lib/auth";

type WSMessage = {
  type: string;
  payload: any;
  sender: string;
  timestamp: string;
};

type WSHandler = (message: WSMessage) => void;

export function useProjectWebSocket(projectId: string | null, handlers: Record<string, WSHandler>) {
  const wsRef = useRef<WebSocket | null>(null);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const handlersRef = useRef(handlers);

  // Keep handlers up to date
  useEffect(() => {
    handlersRef.current = handlers;
  }, [handlers]);

  const connect = useCallback(() => {
    if (!projectId) return;
    const token = getToken();
    if (!token) return;

    const wsUrl = `${process.env.NEXT_PUBLIC_API_BASE_URL?.replace("http", "ws") || "ws://localhost:8000"}/projects/${projectId}/ws?token=${token}`;
    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      setError(null);
      console.log("WebSocket connected for project", projectId);
    };

    ws.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data) as WSMessage;
        const handler = handlersRef.current[message.type];
        if (handler) handler(message);
        // Also call generic handler if exists
        if (handlersRef.current["*"]) {
          handlersRef.current["*"](message);
        }
      } catch (err) {
        console.error("WS message parse error:", err);
      }
    };

    ws.onclose = (event) => {
      setConnected(false);
      if (event.code !== 1000) {
        setError(`Disconnected: ${event.reason || event.code}`);
        // Reconnect after 3 seconds
        reconnectTimeoutRef.current = setTimeout(connect, 3000);
      }
    };

    ws.onerror = (err) => {
      console.error("WebSocket error:", err);
      setError("Connection error");
    };
  }, [projectId]);

  const send = useCallback((type: string, payload: any) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type, payload }));
    }
  }, []);

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }
    wsRef.current?.close(1000, "Client disconnect");
    wsRef.current = null;
  }, []);

  useEffect(() => {
    connect();
    return () => disconnect();
  }, [connect, disconnect]);

  return { connected, error, send, disconnect, reconnect: connect };
}