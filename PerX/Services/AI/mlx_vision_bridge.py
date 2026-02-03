#!/usr/bin/env python3
"""
Bridge Python per modelli vision multimodali usando PyTorch/Transformers
Supporta Llama 3.1 8B Vision e altri modelli vision via Hugging Face
"""

import json
import sys
import os
from pathlib import Path
from typing import Optional, Dict, Any

try:
    import torch
    from transformers import AutoModelForVision2Seq, AutoProcessor
    from PIL import Image
except ImportError as e:
    print(json.dumps({"success": False, "error": f"Import error: {str(e)}. Installa: pip install torch transformers pillow"}), file=sys.stderr, flush=True)
    sys.exit(1)


# Variabili globali per il modello
model = None
processor = None
device = None
dtype = None


def setup_device():
    """Configura device e dtype per PyTorch"""
    global device, dtype
    
    if torch.backends.mps.is_available():
        device = torch.device("mps")
        dtype = torch.float16
        print(f"[MLX Bridge] Usando device: MPS (Apple Silicon)", file=sys.stderr, flush=True)
    else:
        device = torch.device("cpu")
        dtype = torch.float32
        print(f"[MLX Bridge] Usando device: CPU", file=sys.stderr, flush=True)
    
    return device, dtype


def load_model(model_path: str) -> Dict[str, Any]:
    """
    Carica il modello vision e il processor
    
    Args:
        model_path: Percorso al modello (locale) o ID Hugging Face (es. "qresearch/llama-3.1-8B-vision-378")
    
    Returns:
        Dict con success/error
    """
    global model, processor, device, dtype
    
    try:
        print(f"[MLX Bridge] Caricamento modello da: {model_path}", file=sys.stderr, flush=True)
        
        # Setup device se non già fatto
        if device is None:
            setup_device()
        
        # Verifica se è un path locale o un ID Hugging Face
        is_huggingface_id = "/" in model_path and not os.path.exists(model_path) and not os.path.isabs(model_path)
        
        if is_huggingface_id:
            print(f"[MLX Bridge] 📥 Rilevato ID Hugging Face: {model_path}", file=sys.stderr, flush=True)
            print(f"[MLX Bridge] 📥 Download del modello da Hugging Face in corso...", file=sys.stderr, flush=True)
            print(f"[MLX Bridge] ⚠️ Questo può richiedere diversi minuti e diversi GB di spazio...", file=sys.stderr, flush=True)
        else:
            print(f"[MLX Bridge] 📁 Uso modello locale da: {model_path}", file=sys.stderr, flush=True)
            if not os.path.exists(model_path):
                return {"success": False, "error": f"Percorso modello non trovato: {model_path}"}
        
        # Carica il modello (scarica automaticamente se è un ID Hugging Face)
        print(f"[MLX Bridge] Caricamento AutoModelForVision2Seq...", file=sys.stderr, flush=True)
        model = AutoModelForVision2Seq.from_pretrained(
            model_path,
            torch_dtype=dtype,
            low_cpu_mem_usage=True,
            trust_remote_code=True,
        ).to(device)
        
        print(f"[MLX Bridge] Modello caricato su {device}", file=sys.stderr, flush=True)
        
        # Carica il processor
        print(f"[MLX Bridge] Caricamento AutoProcessor...", file=sys.stderr, flush=True)
        processor = AutoProcessor.from_pretrained(
            model_path,
            trust_remote_code=True,
        )
        
        print(f"[MLX Bridge] Processor caricato", file=sys.stderr, flush=True)
        
        return {"success": True}
        
    except Exception as e:
        error_msg = f"Errore nel caricare il modello: {str(e)}"
        print(f"[MLX Bridge] ❌ {error_msg}", file=sys.stderr, flush=True)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return {"success": False, "error": error_msg}


def generate_text(prompt: str, max_tokens: int = 512) -> Dict[str, Any]:
    """
    Genera testo dal prompt (solo testo, senza immagini)
    
    Args:
        prompt: Testo di input
        max_tokens: Numero massimo di token da generare
    
    Returns:
        Dict con success/error e response
    """
    global model, processor, device
    
    try:
        if model is None or processor is None:
            return {"success": False, "error": "Modello non caricato. Esegui prima il comando 'load'."}
        
        print(f"[MLX Bridge] Generazione testo - Prompt: {prompt[:100]}...", file=sys.stderr, flush=True)
        
        # Prepara input solo testo
        inputs = processor(
            text=prompt,
            return_tensors="pt"
        ).to(device)
        
        # Genera
        print(f"[MLX Bridge] Generazione in corso (max_tokens={max_tokens})...", file=sys.stderr, flush=True)
        with torch.no_grad():
            output_ids = model.generate(
                **inputs,
                max_new_tokens=max_tokens,
                do_sample=False,
                temperature=0.0,
            )
        
        # Decodifica
        text = processor.batch_decode(output_ids, skip_special_tokens=True)[0]
        
        # Rimuovi il prompt iniziale dalla risposta se presente
        if text.startswith(prompt):
            text = text[len(prompt):].strip()
        
        print(f"[MLX Bridge] ✅ Testo generato ({len(text)} caratteri)", file=sys.stderr, flush=True)
        
        return {"success": True, "response": text}
        
    except Exception as e:
        error_msg = f"Errore nella generazione: {str(e)}"
        print(f"[MLX Bridge] ❌ {error_msg}", file=sys.stderr, flush=True)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return {"success": False, "error": error_msg}


def analyze_image(image_path: str, prompt: str, max_tokens: int = 512) -> Dict[str, Any]:
    """
    Analizza un'immagine con il modello vision
    
    Args:
        image_path: Percorso assoluto al file immagine
        prompt: Istruzioni per l'analisi
        max_tokens: Numero massimo di token da generare
    
    Returns:
        Dict con success/error e response
    """
    global model, processor, device
    
    try:
        print(f"[MLX Bridge] 🔍 analyze_image chiamato", file=sys.stderr, flush=True)
        print(f"[MLX Bridge] • model is None: {model is None}", file=sys.stderr, flush=True)
        print(f"[MLX Bridge] • processor is None: {processor is None}", file=sys.stderr, flush=True)
        
        if model is None or processor is None:
            error_msg = "Modello non caricato. Esegui prima il comando 'load'."
            print(f"[MLX Bridge] ❌ {error_msg}", file=sys.stderr, flush=True)
            return {"success": False, "error": error_msg}
        
        print(f"[MLX Bridge] 📸 Analisi immagine: {image_path}", file=sys.stderr, flush=True)
        print(f"[MLX Bridge] 💬 Prompt: {prompt}", file=sys.stderr, flush=True)
        
        # Verifica che il file esista
        if not os.path.exists(image_path):
            return {"success": False, "error": f"File immagine non trovato: {image_path}"}
        
        # Carica l'immagine
        try:
            image = Image.open(image_path).convert("RGB")
            print(f"[MLX Bridge] Immagine caricata: {image.size}", file=sys.stderr, flush=True)
        except Exception as e:
            return {"success": False, "error": f"Impossibile aprire l'immagine: {str(e)}"}
        
        # Prepara input multimodali (immagine + testo)
        print(f"[MLX Bridge] Preparazione input multimodali...", file=sys.stderr, flush=True)
        inputs = processor(
            images=image,
            text=prompt,
            return_tensors="pt"
        ).to(device)
        
        # Genera
        print(f"[MLX Bridge] Generazione in corso (max_tokens={max_tokens})...", file=sys.stderr, flush=True)
        with torch.no_grad():
            output_ids = model.generate(
                **inputs,
                max_new_tokens=max_tokens,
                do_sample=False,
                temperature=0.0,
            )
        
        # Decodifica
        text = processor.batch_decode(output_ids, skip_special_tokens=True)[0]
        
        # Rimuovi il prompt iniziale dalla risposta se presente
        if text.startswith(prompt):
            text = text[len(prompt):].strip()
        
        print(f"[MLX Bridge] ✅ Analisi completata ({len(text)} caratteri)", file=sys.stderr, flush=True)
        
        return {"success": True, "response": text}
        
    except Exception as e:
        error_msg = f"Errore nell'analisi: {str(e)}"
        print(f"[MLX Bridge] ❌ {error_msg}", file=sys.stderr, flush=True)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return {"success": False, "error": error_msg}


def main():
    """Main entry point per il bridge"""
    global model, processor
    
    # Setup device all'avvio
    setup_device()
    
    # Verifica argomenti
    if len(sys.argv) < 2:
        result = {"success": False, "error": "Uso: python mlx_vision_bridge.py <command> [args...]"}
        print(json.dumps(result), flush=True)
        sys.exit(1)
    
    command = sys.argv[1]
    print(f"[MLX Bridge] Comando ricevuto: {command}", file=sys.stderr, flush=True)
    
    # Leggi input da stdin (JSON)
    try:
        input_data = json.loads(sys.stdin.read())
        print(f"[MLX Bridge] Input ricevuto: {list(input_data.keys())}", file=sys.stderr, flush=True)
    except json.JSONDecodeError as e:
        result = {"success": False, "error": f"Errore nel parsare JSON input: {str(e)}"}
        print(json.dumps(result), flush=True)
        sys.exit(1)
    except Exception as e:
        input_data = {}
        print(f"[MLX Bridge] ⚠️ Nessun input JSON, uso parametri da argv: {e}", file=sys.stderr, flush=True)
    
    # Esegui comando
    result = None
    
    if command == "load":
        # Carica il modello
        model_path = input_data.get("model_path")
        if not model_path:
            # Prova da argv se disponibile
            model_path = sys.argv[2] if len(sys.argv) > 2 else None
        
        if not model_path:
            result = {"success": False, "error": "Parametro 'model_path' richiesto"}
        else:
            result = load_model(model_path)
    
    elif command == "generate":
        # Genera testo
        model_path = input_data.get("model_path")
        prompt = input_data.get("prompt", "")
        max_tokens = input_data.get("max_tokens", 512)
        
        if not prompt:
            result = {"success": False, "error": "Parametro 'prompt' richiesto"}
        else:
            # Se il modello non è caricato, caricalo prima (ogni processo Python è nuovo)
            if model is None or processor is None:
                if not model_path:
                    result = {"success": False, "error": "Modello non caricato e 'model_path' non fornito. Fornisci 'model_path' nei parametri."}
                else:
                    print(f"[MLX Bridge] Modello non caricato, caricamento automatico da: {model_path}", file=sys.stderr, flush=True)
                    load_result = load_model(model_path)
                    if not load_result.get("success", False):
                        result = load_result
                    else:
                        # Ora che il modello è caricato, genera il testo
                        result = generate_text(prompt, max_tokens)
            else:
                # Modello già caricato, procedi con la generazione
                result = generate_text(prompt, max_tokens)
    
    elif command == "analyze":
        # Analizza immagine
        image_path = input_data.get("image_path")
        model_path = input_data.get("model_path")
        prompt = input_data.get("prompt", "Descrivi questa immagine in dettaglio.")
        max_tokens = input_data.get("max_tokens", 512)
        
        if not image_path:
            result = {"success": False, "error": "Parametro 'image_path' richiesto"}
        else:
            # Se il modello non è caricato, caricalo prima
            if model is None or processor is None:
                if not model_path:
                    result = {"success": False, "error": "Modello non caricato e 'model_path' non fornito. Carica prima il modello con 'load'."}
                else:
                    print(f"[MLX Bridge] Modello non caricato, caricamento automatico da: {model_path}", file=sys.stderr, flush=True)
                    load_result = load_model(model_path)
                    if not load_result.get("success", False):
                        result = load_result
                    else:
                        # Ora che il modello è caricato, analizza l'immagine
                        result = analyze_image(image_path, prompt, max_tokens)
            else:
                # Modello già caricato, procedi con l'analisi
                result = analyze_image(image_path, prompt, max_tokens)
    
    else:
        result = {"success": False, "error": f"Comando sconosciuto: {command}. Comandi validi: load, generate, analyze"}
    
    # Output risultato
    if result is None:
        result = {"success": False, "error": "Nessun risultato generato"}
    
    print(json.dumps(result), flush=True)
    
    # Exit code basato su success
    if not result.get("success", False):
        sys.exit(1)


if __name__ == "__main__":
    main()
