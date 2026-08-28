"""
Misamis Occidental Trip Planner API — Python recommendation engine.

Run: uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from algorithms.planner import plan_trip

app = FastAPI(title="Trip Planner API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class PlanRequest(BaseModel):
    spots: list[dict] = Field(default_factory=list)
    routeAliases: list[str] = Field(default_factory=list)
    municipalitiesOnRoute: list[str] = Field(default_factory=list)
    interests: list[str] = Field(default_factory=list)
    transportMode: str = "Car"
    budget: float = 0
    tripDays: int = 1
    interestWeights: dict[str, float] = Field(default_factory=dict)
    ratedSpotTypes: dict[str, int] = Field(default_factory=dict)
    startMunicipality: str = ""
    endMunicipality: str = ""


@app.get("/health")
def health():
    return {"status": "ok", "engine": "python"}


@app.post("/plan")
def create_plan(body: PlanRequest):
    result = plan_trip(body.model_dump())
    return result


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
