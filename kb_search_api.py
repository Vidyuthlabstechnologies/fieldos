"""Standalone FastAPI server for the construction codes knowledge base (RAG search tool).

This is a separate, optional local tool — NOT part of the FieldOS product (see api.py /
fieldos/app.py for that). It requires advanced_kb.py (untracked, local-only), chromadb,
and a running Ollama instance with nomic-embed-text pulled. None of these are declared in
requirements.txt on purpose: they're heavy and not needed to run FieldOS on a normal laptop.

Run:  python kb_search_api.py
Then: curl http://localhost:8001/query?q=concrete+mix+design
      curl http://localhost:8001/docs  (Swagger UI)
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from advanced_kb import HybridRetriever
from pydantic import BaseModel, Field
from typing import Optional, List
import uvicorn
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="Construction Codes Knowledge Base",
    description="Hybrid semantic search (dense+BM25+cross-encoder on GPU) over Indian construction standards",
    version="3.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

retriever = None


class QueryResult(BaseModel):
    text: str = Field(description="Chunk text content")
    metadata: dict = Field(description="Source info (pdf, pages, heading, etc)")
    score: float = Field(description="Relevance score (cross-encoder sigmoid)")
    rerank_score: Optional[float] = Field(None, description="Cross-encoder rerank score (0-1)")
    dense_score: float = Field(0, description="Dense vector cosine similarity")
    sparse_score: float = Field(0, description="BM25 sparse score")


class QueryResponse(BaseModel):
    query: str
    results: List[QueryResult]
    total: int
    rerank_applied: bool


class QueryRequest(BaseModel):
    q: str = Field(description="Natural language query about construction codes")
    top_k: int = Field(default=5, ge=1, le=50, description="Number of results (1-50)")
    rerank: bool = Field(default=True, description="Apply cross-encoder re-ranking on GPU")
    sources: Optional[str] = Field(
        None,
        description="Filter by source: MoRTH-2013, NBC-2016-Vol2, IRC-SP13-2022, NBC-Guide-2016 (comma-separated)"
    )


def load_retriever():
    global retriever
    print("Loading hybrid retriever...", flush=True)
    retriever = HybridRetriever()
    print("Ready (cross-encoder loads lazily on first query).", flush=True)


@app.get("/health")
def health():
    return {"status": "ok", "chunks": len(retriever.chunks) if retriever else 0}


@app.get("/query", response_model=QueryResponse)
def query_get(
    q: str = Query(description="Natural language query"),
    top_k: int = Query(default=5, ge=1, le=50),
    rerank: bool = Query(default=True),
    sources: Optional[str] = Query(default=None),
):
    return _query(q, top_k, rerank, sources)


@app.post("/query", response_model=QueryResponse)
def query_post(body: QueryRequest):
    return _query(body.q, body.top_k, body.rerank, body.sources)


def _query(q: str, top_k: int, rerank: bool, sources: Optional[str]):
    results = retriever.retrieve(q, top_k=top_k, rerank=rerank, sources=sources)
    return QueryResponse(
        query=q,
        results=[QueryResult(**r) for r in results],
        total=len(results),
        rerank_applied=rerank,
    )


if __name__ == "__main__":
    load_retriever()
    uvicorn.run(app, host="0.0.0.0", port=8001, log_level="info")
