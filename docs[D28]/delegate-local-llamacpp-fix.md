---
date: "2026-07-04 21:35"
type: memory_db
tags: [delegate_local, lmstudio, llama-server, gemma-4-12b, fix, provider, delegation]
---

# delegate-local-lmstudio-fix

# Fix delegate_local 404 — provider "local" → "lmstudio"

## Date
2026-07-04

## Problème
`delegate_local` utilisait `provider="local"` (delegate_variants.py:187) qui n'existe PAS dans `~/.hermes/config.yaml`. Le résolveur `resolve_runtime_provider("local")` échoue → 404.

## Fix
Patch: `provider="local"` → `provider="lmstudio"` dans `delegate_variants.py:187`.

Le provider `lmstudio` pointe vers `http://localhost:1234/v1` (llama-server).

## Lancement llama-server (32K contexte)
```bash
CUDA_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=/home/moussa/.local/share/llama-server-cuda \
  /home/moussa/.local/share/llama-server-cuda/llama-server \
  -m ~/Documents/Hermes_Workspace/LLM_MODELS/GGUF/gemma-4-12b-it-Q4_K_M.gguf \
  --host 127.0.0.1 --port 1234 -ngl 99 -c 32768 --reasoning off \
  --alias gemma-4-12b-it
```
- VRAM: 9.4 GB sur RTX 3060 12GB
- `--alias gemma-4-12b-it` obligatoire
- `--reasoning off` obligatoire

## Test 3 tâches (2026-07-04)
- Tâche 1: diagnostic GPU (terminal, write_file, read_file) — 16s, 4 outils
- Tâche 2: recherche web + analyse (web_search, web_extract, terminal, write_file, read_file) — 44s, 6 outils
- Tâche 3: synthèse + rapport (search_files, read_file, terminal, write_file) — 27s, 5 outils
- Total: 15 appels outils, 87s, 0 erreur
- Fichiers: /home/moussa/Bureau/test-delegation/task{1,2,3}_*.txt

## Conclusion
`delegate_local` fonctionne après le patch provider. Le subagent utilise bien les outils terminal, file, web, search_files.

---
date: "2026-07-04 23:10"
type: memory_db
tags: [delegate_local, minimum_context_length, venv, llama-server, LD_LIBRARY_PATH, provider-fix, lmstudio]
---

# delegate-local-fixes-2026-07-04

# delegate_local fixes (2026-07-04 session 4)

## Provider fix appliqué
- `delegate_variants.py:203` : `provider="local"` → `provider="lmstudio"` dans `~/Applications/HERMES_LITE/src/tools/delegate_variants.py`
- Le provider "local" n'existait pas dans config.yaml → 404

## MINIMUM_CONTEXT_LENGTH dual-path
- Hermes venv charge depuis `~/.hermes/hermes-agent/agent/` PAS `~/Applications/HERMES_LITE/src/agent/`
- editable install `.pth` file mapping `agent` → `~/.hermes/hermes-agent/agent/`
- Fallait patcher `~/.hermes/hermes-agent/agent/model_metadata.py:133` : 64_000 → 16_384
- Redémarrage Hermes obligatoire (process en cours garde ancienne valeur en mémoire)

## LD_LIBRARY_PATH
- `llama-server` a besoin de `libllama-server-impl.so` dans `~/.local/lib/`
- Lancer avec `LD_LIBRARY_PATH=/home/moussa/.local/lib:/home/moussa/.local/share/llama-server-cuda`

## Statut final
- Fixes appliqués mais redémarrage HL nécessaire pour que delegate_local fonctionne
- llama-server opérationnel sur port 1234 avec gemma-4-12b-it

---
date: "2026-07-04 21:22"
type: memory_db
tags: [llama-server, delegate_local, lmstudio, gemma-4-12b, provider, delegation]
---

# delegate-local-llama-server-fix

# Délégation locale — llama-server + delegate_local

## Problème delegate_local (404)
`delegate_local` utilise `provider="local"` qui n'existe PAS dans `~/.hermes/config.yaml` → `resolve_runtime_provider("local")` échoue.

## Solution qui marche
Utiliser `delegate_task(provider="lmstudio", model="gemma-4-12b-it")` car le provider `lmstudio` est déclaré dans `providers:` avec `api: http://localhost:1234/v1`.

## Lancement llama-server
```bash
CUDA_VISIBLE_DEVICES=0 LD_LIBRARY_PATH=/home/moussa/.local/share/llama-server-cuda \
  /home/moussa/.local/share/llama-server-cuda/llama-server \
  -m ~/Documents/Hermes_Workspace/LLM_MODELS/GGUF/gemma-4-12b-it-Q4_K_M.gguf \
  --host 127.0.0.1 --port 1234 -ngl 99 -c 4096 --reasoning off --alias gemma-4-12b-it
```

**`--alias gemma-4-12b-it` obligatoire** pour que le modèle soit exposé sous le nom court au lieu de `gemma-4-12b-it-Q4_K_M.gguf`.

## Notes
- Le model override de `delegate_task` n'est PAS propagé au subagent — il utilise le modèle par défaut (`glm-5.2-cloud`).
- Mais la tâche s'exécute quand même correctement avec le modèle par défaut.
- Pour vraiment utiliser le modèle local, il faudrait que le modèle par défaut de l'agent soit local, ou patcher `delegate_variants.py` pour passer `base_url` au lieu de `provider`.
