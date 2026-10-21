# RAPPORT — GEMMA 4 12B UNIFIED (GGUF Q4_K_M)

**Date :** 14/06/2026
**Source officielle :** huggingface.co/google/gemma-4-12b-it (README, 27K chars)
**Fichier :** `~/Documents/Hermes_Workspace/LLM_MODELS/GGUF/gemma-4-12b-it-Q4_K_M.gguf`

---

## 1. Architecture

| Caractéristique | Valeur |
|---|---|
| Paramètres totaux | 11.95 B |
| Type | Dense (pas MoE) |
| Couches | 48 |
| Sliding Window | 1024 tokens |
| **Contexte natif** | **256K tokens** |
| Vocabulaire | 262K |
| Attention | Hybride (sliding window local + global intercalé, dernière couche toujours globale) |
| Architecture | "Unified" = encoder-free (pas de vision encoder séparé, tout est dans le LLM) |
| Multimodal | Texte + image + audio (audio via encodeur ~300M params) |
| Licence | Apache 2.0 |

---

## 2. Mode Thinking (Raisonnement)

**CE N'EST PAS UN BUG DE CONVERSION GGUF.** C'est un design Google.

### Comment ça marche (doc officielle)
- Le thinking est activé par le token `<|think|>` au début du prompt système
- `enable_thinking=True` → le modèle génère d'abord `<|channel>thought\n` [raisonnement] `<channel|>` puis la réponse
- `enable_thinking=False` → le modèle génère les balises vides puis la réponse directement
- En multi-tour, seul le contenu final (pas la pensée) doit être inclus dans l'historique

### Ce qu'on a observé
- **`--reasoning off` (enable_thinking=False)** → le modèle sort les balises vides + réponse → **marche parfaitement** (5/5 précis)
- **`--reasoning auto`** → boucle infinie de thinking, jamais de content → **inutilisable**
- **`enable_thinking: false` dans l'API** → ignoré par llama-server, le flag CLI prime

### Pourquoi la boucle infinie ?
Le modèle entre en mode thinking mais ne rencontre jamais le token de fin `<channel|>`. Causes possibles :
1. Le `max_tokens` est atteint avant la fin du raisonnement (le modèle pense trop longtemps)
2. Le prompt ne donne pas assez de contexte pour que le modèle décide de s'arrêter de penser
3. La conversion GGUF a peut-être mal géré les tokens de contrôle

**Solution retenue :** `--reasoning off` + bon prompt avec exemples (AGENTS_Gemma.md). Le modèle sans thinking est déjà excellent.

---

## 3. VRAM — Mesures réelles sur RTX 3060 12 GB

| Configuration | Modèle | Cache KV | Total mesuré |
|---|---|---|---|
| 32K contexte (actuel) | ~4.8 GB | ~0.9 GB | **5.9 GB** |

### Projections (basées sur 12 KB/token avec q4_0 et n_kv_heads=1)

| Contexte | Cache KV | Total estimé | Faisable ? |
|---|---|---|---|
| 32K | 0.4 GB | 5.7 GB | ✅ Mesuré |
| 64K | 0.8 GB | 6.1 GB | ✅ Large |
| 128K | 1.6 GB | 6.9 GB | ✅ Confortable |
| 192K | 2.4 GB | 7.7 GB | ✅ |
| 256K | 3.1 GB | 8.4 GB | ✅ Possible ! |

**⚠️ Le crash à 48K était dû à un split Vulkan sur 2 GPUs, pas un vrai OOM.** Avec `CUDA_VISIBLE_DEVICES=0`, le 48K n'a jamais été testé proprement.

---

## 4. Performance vs 14B Coder

| Critère | Qwen 14B Coder | Gemma 4 12B |
|---|---|---|
| Contexte max | 16K (limité par VRAM) | **256K (natif)** — testé 32K, 64K+ possible |
| VRAM (modèle) | 8.5 GB (Q4_K_M) | **4.8 GB** (Q4_K_M) |
| VRAM (32K total) | 6.8 GB | **5.9 GB** |
| Temps/lot (3 mots) | 12s | 19s (system prompt 3K tokens) → 5.5s sans |
| Tokens/lot | 600→100 | 1400→50 (system prompt lourd) |
| Précision classification | ~70% (copie-colle 0001) | **100%** (avec AGENTS.md + exemples) |
| Bug principal | FF/FF/0001 par défaut | Thinking boucle infinie (résolu via `--reasoning off`) |

---

## 5. Conclusion

**Gemma 4 12B est le meilleur modèle local pour nos besoins :**
- **Classification neurones S** : 100% précis avec AGENTS_Gemma.md, 3x moins de VRAM que le 14B
- **256K contexte natif** : peut absorber des définitions entières + contexte RA complet
- **Pipeline V8** : tourne actuellement à 32K, 110K neurones restants, ~19s/lot
- **Futur** : le thinking pourrait être corrigé avec un meilleur prompt ou une mise à jour llama-server

**Prochaine étape** : tester 64K puis 128K de contexte pour réduire encore les coûts (moins de lots = plus de mots par lot).