---
date: "2026-07-06 11:47"
type: memory_db
tags: [scripts, centralisation, llm_syntaxique, system, rangements]
---

# scripts_centralises_06_07_2026

# Scripts centralisés — 06/07/2026

## Emplacement
`~/Scripts/` — dossier unique pour tous les scripts du système

### `~/Scripts/llm_syntaxique/` (21 scripts)
- `train_grammairien.py` + `train_grammairien.sh` — entraînement modèle
- `pre_tokenize.py` — pré-tokenisation datasets
- `tokenize_file.py` — tokenisation single file
- `monitor_pipeline.sh` — surveillance pipeline
- `pipeline_regles.py` — règles du pipeline
- `rapport_entrainement.sh` — rapport entraînement
- `build_tokenizer.py` — construction tokenizer
- `etape1_corpus_flux.py`, `fluxer_corpus.py`, `flux_gallica.py` — pipeline flux
- `parquet_to_phrases.py` — extraction parquet
- `run_spacy_gallica.py`, `run_spacy_v2_resume.py` — spacy
- `s1_corpus_morphalou.py`, `s1_morphalou.py` — étape 1 morphalou
- `s2_spacy_gemini_v2.py` — étape 2 spacy+gemini
- `s3_nombre_verbe.py` — étape 3 nombre/verbe
- `s5_qualite.py` — étape 5 qualité
- `split_gallica.py` — split train/val
- `verif_qualite_chunks.py` — vérification qualité chunks

### `~/Scripts/system/` (5 scripts)
- `fix-tablette.sh` — fix tablette
- `RA_Cockpit.sh` — cockpit RA
- `train.sh` — raccourci entraînement
- `commit_before.sh` — pre-commit
- `gitea_watcher.sh` — surveillance gitea

## Symlinks
Les anciens emplacements dans `LLM_SYNTAXIQUE/` et `LLM_SYNTAXIQUE/SCRIPTS/` sont des symlinks vers `~/Scripts/llm_syntaxique/` pour ne pas casser l'entraînement en cours.

## ~/.local/bin/ (inchangé)
Scripts système dans le PATH : `bottle.py`, `dumppdf.py`, `pdf2txt.py`, `websearch.sh`, `open-webui-launcher.sh`, `open-webui-wrapper.sh`, `event_rpcgen.py`
