#!/usr/bin/env python3
"""rank_tools.py - LE SELECTEUR. Une demande + une LISTE FINIE de candidats -> un classement.

PRINCIPE (MOUSSA). Le selecteur recoit la demande ET les candidats, et rend un SCORE par
candidat. On ne garde jamais un nombre fixe de tools : on garde une PART de la liste
(30% de 18 = 6 tools). L'echelle est degressive cote agent : 30% au premier appel, 60% au
deuxieme, 100% au troisieme -- au troisieme la liste entiere est ouverte, donc le rattrapage
est garanti. Ce qui compte n'est pas que le bon tool soit LE PREMIER, mais qu'il SOIT DANS LA
LISTE LIVREE.

RIEN N'EST INVENTE ICI. Les candidats viennent du PERIMETRE du tour (la palette du skill
actif + la categorie permanente), ecrit par l'appelant dans un fichier : une ligne par
candidat, au format `id|nom|description` -- le meme format que l'ancien releve de plongements,
pour que la mesure reste comparable.

USAGE
  printf '%s\\n' "<la demande>" | rank_tools.py --candidates <fichier> [--share 30] [--port 8095]

SORTIE (ce que le modele lit)
  une ligne d'entete : n candidats, part demandee, k retenus
  puis k lignes, du meilleur au moins bon : "score  nom"
  une derniere ligne : le rappel de l'echelle (30 -> 60 -> 100)

SORTIE D'ERREUR : un refus NOMME, sur la sortie d'erreur, code 1. Jamais de resultat partiel
silencieux.
"""

import argparse
import json
import math
import os
import sys
import urllib.error
import urllib.request

REFUS = 1


def refus(message):
    print("refuse : %s" % message, file=sys.stderr)
    sys.exit(REFUS)


def main():
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--candidates", required=True)
    p.add_argument("--share", default="30")
    p.add_argument("--port", default=os.environ.get("LA_RERANK_PORT", "8095"))
    p.add_argument("--host", default=os.environ.get("LA_RERANK_HOST", "127.0.0.1"))
    a, _ = p.parse_known_args()

    # LA PART : bornee, jamais un nombre de tools en dur.
    try:
        part = int(str(a.share).strip() or "30")
    except ValueError:
        refus("la part n'est pas un nombre (%r) ; elle s'ecrit en pourcentage, ex. 30" % a.share)
    if part < 1:
        part = 1
    if part > 100:
        part = 100

    demande = sys.stdin.read().strip()
    if not demande:
        refus("rien a classer ; la demande entre par l'entree standard")

    if not os.path.isfile(a.candidates):
        refus("la liste des candidats est introuvable (%s)" % a.candidates)
    docs, noms = [], []
    with open(a.candidates, encoding="utf-8") as f:
        for ligne in f:
            ligne = ligne.strip()
            if not ligne:
                continue
            morceaux = ligne.split("|", 2)
            if len(morceaux) == 3:
                docs.append(ligne)
                noms.append(morceaux[1])
    if not docs:
        refus("la liste des candidats est vide (%s)" % a.candidates)

    corps = json.dumps({"query": demande, "documents": docs,
                        "top_n": len(docs)}).encode("utf-8")
    url = "http://%s:%s/v1/rerank" % (a.host, a.port)
    try:
        req = urllib.request.Request(url, data=corps,
                                     headers={"Content-Type": "application/json"})
        reponse = json.loads(urllib.request.urlopen(req, timeout=180).read())
    except urllib.error.URLError as e:
        refus("le resident de classement ne repond pas sur %s (%s) ; lance : rerank.sh start" % (url, e))
    except ValueError as e:
        refus("la reponse du resident de classement est illisible (%s)" % e)

    resultats = reponse["results"] if isinstance(reponse, dict) and "results" in reponse else reponse
    notes = []
    for item in resultats:
        i = int(item["index"])
        if 0 <= i < len(noms):
            notes.append((float(item["relevance_score"]), noms[i]))
    if not notes:
        refus("le resident de classement n'a rendu aucun score (%s)" % url)

    notes.sort(key=lambda x: -x[0])
    garde = max(1, math.ceil(part / 100.0 * len(notes)))

    print("%d candidats, part %d%% = %d retenu(s)" % (len(notes), part, garde))
    for score, nom in notes[:garde]:
        print("%8.3f  %s" % (score, nom))
    if part < 100:
        suivant = 60 if part <= 30 else 100
        print("si le tool voulu n'y est pas : rappelle rank_tools avec share=%d" % suivant)


if __name__ == "__main__":
    main()
