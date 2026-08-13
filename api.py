"""FastAPI server for construction codes knowledge base.
Designed for AI agent function-calling — structured request/response.

Run:  python api.py
Then: curl http://localhost:8000/query?q=concrete+mix+design
      curl http://localhost:8000/docs  (Swagger UI)
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

from fieldos.routers import companies, dashboard, dpr, estimation, issues, projects, tasks

app.include_router(companies.router)
app.include_router(projects.router)
app.include_router(tasks.router)
app.include_router(dpr.router)
app.include_router(issues.router)
app.include_router(estimation.router)
app.include_router(dashboard.router)

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
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
