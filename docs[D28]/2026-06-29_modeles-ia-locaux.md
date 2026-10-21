---
date: "2026-06-29"
type: infos
tags: ["modèles", "ia", "gpu"]
---

## llama.cpp (port 1234, RTX 3060 12Go)
- **Qwen2.5-Coder-14B-Instruct-Q4_K_M** — 16K ctx, NGL 48
- **Qwen2.5-14B-Instruct-Q4_K_M** — 16K ctx, NGL 48
- **Qwen2.5-Coder-7B-Instruct-Q4_K_M** — 32K ctx, NGL all
- **Phi-4-mini-instruct-Q4_K_M** — 32K ctx, NGL all
- **Phi-4-mini-reasoning-Q4_K_M** — 32K ctx, NGL all
- **Gemma-4-E4B-it-Q4_K_M** — 32K ctx, NGL all
- Qwen 3 VL 8B- Q4

Stockage: `~/Documents/Hermes_Workspace/LLM_MODELS/GGUF/`

## ComfyUI (port 8188)
- SDXL, SD1.5, modèles custom
- Dossier modèles: `ComfyUI/models/checkpoints/`

## Remote (API)
- **DeepSeek V4 flash** (deepseek-chat) — 1M ctx, $0.14/$0.28 par M tokens
- **OpenRouter** — fallback (Claude, Gemini)