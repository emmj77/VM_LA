---
date: "2026-07-04 21:41"
type: memory_db
tags: [llama.cpp, provider, local, lmstudio, gemma, delegate_local]
---

# hermes_provider_local

# Provider Local = llama.cpp

## Configuration
- base_url: `http://127.0.0.1:1234/v1`
- Alias interne Hermes: `lmstudio` (alias de llama.cpp, pas LM Studio réel)
- Modèle: `gemma-4-12b-it`
- Check disponibilité: `_llama_server_running()` ping `localhost:1234/health`
- Fallback: `delegate_ollama` si serveur down

## Lancement llama-server
```bash
llama-server --model gemma-4-12b-it.gguf --port 1234 --alias gemma-4-12b-it
```

## Notes
- GLM peut citer "LMStudio" → c'est l'alias interne, pas une hallucination
- Endpoint 1234/v1 est bien llama.cpp
