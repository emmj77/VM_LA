---
date: "2026-07-04 21:41"
type: memory_db
tags: [num_predict, max_tokens, ollama, verbosite]
---

# hermes_num_predict_max_tokens

# Parametres de longueur de reponse

## Ollama local
- `num_predict=300` borne le nombre de tokens generes

## ollama-cloud (GLM)
- le parametre equivalent est `max_tokens`
- `num_predict` est ignore

## Levier principal
- une regle d'entrelacement (1 phrase -> outil -> 1 phrase) dans le head tient la verbosite
- elle est plus efficace que les parametres techniques (`num_predict`, `max_tokens`)
