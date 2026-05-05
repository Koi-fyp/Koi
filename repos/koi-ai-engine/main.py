"""
KOI AI Engine - FastAPI Microservice Entry Point
Option B: Decoupled microservice architecture with Firebase JWT authentication
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import psutil

from app.core.config import settings
from app.core.security import verify_firebase_token
from app.middleware.auth_middleware import FirebaseAuthMiddleware
from app.api import router as api_router

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup/shutdown events"""
    logger.info("KOI AI Engine starting up...")
    yield
    logger.info("KOI AI Engine shutting down...")


# Initialize FastAPI application
app = FastAPI(
    title="KOI AI Engine",
    description="Decoupled microservice for LLM inference and user engagement analysis",
    version="0.1.0",
    lifespan=lifespan,
)

# Configure CORS to allow only trusted origins
origins = settings.allowed_origins

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["X-Process-Time"],
)

app.add_middleware(FirebaseAuthMiddleware)


@app.get("/health", tags=["system"])
async def health_check():
    """
    Health check endpoint that returns system status.

    Returns:
        dict: System health status including CPU, memory, and service uptime
    """
    try:
        cpu_percent = psutil.cpu_percent(interval=0.1)
        memory = psutil.virtual_memory()

        status_code = "healthy" if cpu_percent < 90 and memory.percent < 85 else "degraded"

        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={
                "status": status_code,
                "service": "koi-ai-engine",
                "version": "0.1.0",
                "cpu_percent": cpu_percent,
                "memory_percent": memory.percent,
                "memory_available_mb": int(memory.available / (1024 * 1024)),
            }
        )
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "unhealthy", "error": str(e)}
        )


@app.get("/ai/warmup", tags=["system"])
async def warmup_model():
    """
    Warm-up endpoint to mitigate Render free-tier spin-down delays.

    This endpoint performs a lightweight operation to keep the service
    active and prevent cold starts from impacting user experience.

    Returns:
        dict: Warmup completion status
    """
    logger.info("Warmup requested")
    return {
        "status": "ready",
        "message": "AI engine warmed up",
        "timestamp": str(__import__('datetime').datetime.utcnow()),
    }


@app.post("/ai/inference", tags=["inference"])
async def run_inference(
    payload: dict,
    current_user: dict = Depends(verify_firebase_token)
):
    """
    Main inference endpoint for LLM processing.

    Requires:
        - Authorization header with valid Firebase JWT token
        - payload: Request body with inference parameters

    Returns:
        dict: Inference results with user engagement analysis
    """
    logger.info(f"Inference requested by user {current_user.get('uid', 'unknown')}")

    # Placeholder for actual inference logic
    return {
        "status": "success",
        "user_id": current_user.get("uid"),
        "message": "Inference endpoint ready (implementation pending)",
    }


app.include_router(api_router)


@app.get("/", tags=["root"])
async def root():
    """Root endpoint with API information"""
    return {
        "service": "KOI AI Engine",
        "version": "0.1.0",
        "docs": "/docs",
        "health": "/health",
        "warmup": "/ai/warmup",
    }


# ============================================================================
# Error Handlers
# ============================================================================

@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    """Handle HTTP exceptions"""
    logger.warning(f"HTTP exception: {exc.status_code} - {exc.detail}")
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.detail},
    )


@app.exception_handler(Exception)
async def general_exception_handler(request, exc):
    """Handle general exceptions"""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": "Internal server error"},
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level="info",
    )
