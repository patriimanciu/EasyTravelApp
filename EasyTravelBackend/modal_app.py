"""
Deploy EasyTravel FastAPI backend on Modal.

Prerequisites:
  1. pip install modal && modal setup
  2. Create a Modal Secret named "easytravel-openai" with key OPENAI_API_KEY
     (Modal dashboard → Secrets, or: modal secret create easytravel-openai OPENAI_API_KEY=sk-...)

Run from this directory (EasyTravelBackend):
  modal serve modal_app.py    # dev: temporary URL, hot reload
  modal deploy modal_app.py   # prod: stable URL printed at the end

Use the printed URL in the iOS app as base URL, e.g.:
  https://YOUR-WORKSPACE--easytravel-api-serve.modal.run/
  (Swift BackendClient will POST to .../api/process-video)
"""

from __future__ import annotations

import pathlib

import modal

# Directory that contains main.py and whisper_service.py
_BACKEND_DIR = pathlib.Path(__file__).resolve().parent

app = modal.App("easytravel-api")

# FFmpeg required by yt-dlp audio extraction; Whisper + PyTorch are heavy — increase memory if OOM.
image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg", "tesseract-ocr")
    .pip_install(
        "fastapi[standard]",
        "uvicorn[standard]",
        "openai",
        "pydantic",
        "yt-dlp",
        "openai-whisper",
        "numpy",
        "pillow",
        "pytesseract",
    )
    # Keep yt-dlp current — YouTube/TikTok CDNs change often; stale builds hit HTTP 403 on video.
    .run_commands(
        "pip install -U yt-dlp",
        "pip install torch --index-url https://download.pytorch.org/whl/cpu",
    )
    .add_local_dir(
        _BACKEND_DIR,
        remote_path="/root/backend",
        copy=True,
        # dockerignore-style: skip huge local venv / caches
        ignore=["**/venv/**", "**/.venv/**", "**/__pycache__/**", "**/*.pyc"],
    )
)


@app.function(
    image=image,
    secrets=[modal.Secret.from_name("easytravel-openai")],
    timeout=30 * 60,  # 30 min — download + whisper can be slow
    memory=8192,  # MB; raise if Whisper OOMs
    # Optional: faster transcription (costs GPU time)
    gpu="T4",
)
@modal.concurrent(max_inputs=4)
@modal.asgi_app()
def serve():
    import sys

    sys.path.insert(0, "/root/backend")
    from main import app as fastapi_app

    return fastapi_app
