#!/usr/bin/env python3
"""
MLX Vision Bridge Server
Espone i modelli MLX Vision via HTTP per l'Hub Swift
"""

import asyncio
import base64
import io
import json
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

# MLX imports (condizionali)
try:
    import mlx.core as mx
    from mlx_lm import load, generate
    from mlx_vlm import load as load_vlm, generate as generate_vlm
    from mlx_vlm.prompt_utils import apply_chat_template
    from mlx_vlm.utils import load_config
    MLX_AVAILABLE = True
except ImportError:
    MLX_AVAILABLE = False
    print("⚠️ MLX non disponibile, il server funzionerà in modalità mock")

from PIL import Image

app = FastAPI(title="MLX Vision Bridge", version="1.0.0")

# Modello caricato
model = None
processor = None
config = None
current_model_name: Optional[str] = None


class AnalyzeRequest(BaseModel):
    model: str = "mlx-community/Qwen2.5-VL-7B-Instruct-8bit"
    image: str  # Base64 encoded
    prompt: str


class AnalyzeResponse(BaseModel):
    result: str
    model: str
    tokens_generated: int


class HealthResponse(BaseModel):
    status: str
    mlx_available: bool
    model_loaded: bool
    model_name: Optional[str]


@app.get("/health", response_model=HealthResponse)
async def health():
    """Health check"""
    return HealthResponse(
        status="ok",
        mlx_available=MLX_AVAILABLE,
        model_loaded=model is not None,
        model_name=current_model_name
    )


@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(request: AnalyzeRequest):
    """Analizza un'immagine con il modello vision"""
    global model, processor, config, current_model_name
    
    if not MLX_AVAILABLE:
        # Modalità mock per sviluppo
        return AnalyzeResponse(
            result=f"[MOCK] Analisi immagine con prompt: {request.prompt[:100]}...",
            model="mock",
            tokens_generated=0
        )
    
    try:
        # Carica modello se necessario
        if model is None or current_model_name != request.model:
            print(f"🔄 Caricamento modello: {request.model}")
            model, processor = load_vlm(request.model)
            config = load_config(request.model)
            current_model_name = request.model
            print(f"✅ Modello caricato: {request.model}")
        
        # Decodifica immagine
        image_data = base64.b64decode(request.image)
        image = Image.open(io.BytesIO(image_data))
        
        # Prepara prompt
        formatted_prompt = apply_chat_template(
            processor,
            config,
            request.prompt,
            num_images=1
        )
        
        # Genera risposta
        output = generate_vlm(
            model,
            processor,
            image,
            formatted_prompt,
            max_tokens=1024,
            temp=0.7,
            verbose=False
        )
        
        return AnalyzeResponse(
            result=output,
            model=request.model,
            tokens_generated=len(output.split())  # Approssimativo
        )
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/unload")
async def unload_model():
    """Scarica il modello dalla memoria"""
    global model, processor, config, current_model_name
    
    model = None
    processor = None
    config = None
    current_model_name = None
    
    # Forza garbage collection
    import gc
    gc.collect()
    
    if MLX_AVAILABLE:
        mx.metal.clear_cache()
    
    return {"status": "unloaded"}


if __name__ == "__main__":
    print("🚀 Avvio MLX Vision Bridge su porta 8765...")
    uvicorn.run(app, host="0.0.0.0", port=8765)
