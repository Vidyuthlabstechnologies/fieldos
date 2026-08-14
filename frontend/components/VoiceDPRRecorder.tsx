"use client";

import { useRef, useState } from "react";

import { createDprVoiceDraft, type DPRVoiceDraft } from "@/lib/api";

export function VoiceDPRRecorder({
  projectId,
  onDraft,
}: {
  projectId: string;
  onDraft: (draft: DPRVoiceDraft) => void;
}) {
  const [state, setState] = useState<"idle" | "recording" | "transcribing" | "error">("idle");
  const [error, setError] = useState<string | null>(null);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);

  async function startRecording() {
    setError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream);
      chunksRef.current = [];
      recorder.ondataavailable = (e) => chunksRef.current.push(e.data);
      recorder.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        const blob = new Blob(chunksRef.current, { type: "audio/webm" });
        setState("transcribing");
        try {
          const draft = await createDprVoiceDraft(projectId, blob);
          onDraft(draft);
          setState("idle");
        } catch (err) {
          setError(err instanceof Error ? err.message : "Transcription failed");
          setState("error");
        }
      };
      mediaRecorderRef.current = recorder;
      recorder.start();
      setState("recording");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't access microphone");
      setState("error");
    }
  }

  function stopRecording() {
    mediaRecorderRef.current?.stop();
  }

  return (
    <div className="flex items-center gap-2">
      {state === "recording" ? (
        <button
          onClick={stopRecording}
          type="button"
          className="rounded bg-red-600 px-3 py-1.5 text-sm text-white"
        >
          Stop recording
        </button>
      ) : (
        <button
          onClick={startRecording}
          disabled={state === "transcribing"}
          type="button"
          className="rounded border border-slate-300 px-3 py-1.5 text-sm disabled:opacity-50"
        >
          {state === "transcribing" ? "Transcribing..." : "Record voice DPR"}
        </button>
      )}
      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  );
}
