#!/usr/bin/python3
# french in code is forbidden
import ast
import glob
import json
import os
import re
import subprocess
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HUNSPELL = "/usr/share/hunspell"
ENGLISH_KEEP = set("anima conf environ vals tris profiler verts flac destin frame config data meta json yaml python dash shell bash args argv stdin stdout stderr tmp dir dirs src dest repo branch commit diff merge push pull stash key keys item items list lists map maps node nodes".split())

STOP = set("""
demande demandes reponse reponses outil outils corps ligne lignes nom noms valeur valeurs texte textes
sujet sujets rendu borne bornes seuil voix mot mots cible cibles lien liens lecture ecriture attente erreur
erreurs raison loi lois separes attendu doit doivent peut veut exige inconnu inconnue ecrit ecrite appelle
appellent sert vaut etre rien moins meme encore apres avant chaque autre autres tourne tournent arrete
ouvert ouverte ferme fermee verrou approbation portee jetons appels duree etape etapes calque calques dessin
brique briques memoire temporaire entree sortie dossier dossiers fichier fichiers nombre refus choix poids
heure heures propre libre gauche droite debut tete cote clef reglage regles poser ecrire lire lancer arreter
relancer attendre trouve cherche rendre recu perdu garde compte ajoute retire sortir rentrer monter descend
ouvre plein moitie fois niveau etat etats humain projet projets fenetre ecran ecrans tot quoi dedans morceau
morceaux chemin chemins fonction fonctions propres resultat resultats mesure mesures modifie supprime cree
choisi pret prete occupe seconde secondes jour jours semaine semaines mois annee couleur couleurs
""".split())

ACCENT = "\u00e9\u00e8\u00ea\u00eb\u00e0\u00e2\u00e7\u00f9\u00fb\u00f4\u00ee\u00ef\u00ff\u0153"


def strip(word):
    return "".join(c for c in unicodedata.normalize("NFD", word.lower()) if unicodedata.category(c) != "Mn")


def load_dic(path):
    out = set()
    try:
        with open(path, encoding="utf-8", errors="ignore") as handle:
            next(handle)
            for line in handle:
                word = line.split("/")[0].strip()
                if word:
                    out.add(strip(word))
    except OSError:
        pass
    return out


FR = load_dic(os.path.join(HUNSPELL, "fr.dic")) | STOP
EN = load_dic(os.path.join(HUNSPELL, "en_US.dic"))


def aspell_bad(words, lang):
    if not words:
        return set()
    proc = subprocess.run(["aspell", "-l", lang, "list"], input="\n".join(sorted(words)), capture_output=True, text=True)
    return {line.strip() for line in proc.stdout.splitlines() if line.strip()}


SEEN = set()
ONLY_FR = None


def build_oracle(raw):
    global ONLY_FR
    split = set()
    for word in raw:
        split.update(w for w in re.split(r"[^0-9A-Za-z]+", str(word)) if w)
    raw = split
    plain = {str(w).lower() for w in raw if len(str(w)) >= 4 and not any(c in str(w) for c in ACCENT)}
    plain -= ENGLISH_KEEP
    en_ok = plain - aspell_bad(plain, "en")
    fr_ok = plain - aspell_bad(plain, "fr")
    ONLY_FR = (fr_ok - en_ok) | {str(w) for w in raw if any(c in str(w) for c in ACCENT)}


def french(name):
    raw = str(name)
    if any(c in raw.lower() for c in ACCENT):
        return True
    if ONLY_FR is None:
        return False
    for token in re.split(r"[^0-9A-Za-z]+", raw.lower()):
        if len(token) < 4:
            continue
        if token in ONLY_FR or token.rstrip("s") in ONLY_FR:
            return True
    return False


def files(pattern):
    return sorted(glob.glob(os.path.join(ROOT, pattern)))


def audit_python(path, problems):
    src = open(path, encoding="utf-8").read()
    try:
        tree = ast.parse(src)
    except SyntaxError as error:
        problems.append(("python", path, "syntax", str(error)))
        return
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            names.add(node.id)
        elif isinstance(node, ast.arg):
            names.add(node.arg)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.Attribute):
            names.add(node.attr)
        elif isinstance(node, (ast.Global, ast.Nonlocal)):
            names.update(node.names)
    for name in sorted(names):
        if french(name):
            problems.append(("python", path, "identifier", name))


def audit_shell(path, problems):
    for line in open(path, encoding="utf-8"):
        code = re.split(r"(?:^|\s)#", line)[0]
        for match in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=", code):
            if french(match.group(1)):
                problems.append(("shell", path, "variable", match.group(1)))
        for match in re.finditer(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)", code):
            if french(match.group(1)):
                problems.append(("shell", path, "function", match.group(1)))


def audit_js(path, problems):
    src = open(path, encoding="utf-8").read()
    for match in re.finditer(r"\b(?:const|let|var|function)\s+([A-Za-z_$][\w$]*)", src):
        if french(match.group(1)):
            problems.append(("javascript", path, "identifier", match.group(1)))
    for match in re.finditer(r"\.\s*([A-Za-z_$][\w$]{3,})\s*\(", src):
        if french(match.group(1)):
            problems.append(("javascript", path, "method", match.group(1)))
    for match in re.finditer(r"[.\[]\s*[\"']?([A-Za-z_$][\w$]{3,})[\"']?\s*[\]=]", src):
        if french(match.group(1)):
            problems.append(("javascript", path, "property", match.group(1)))


def audit_yaml(path, problems, keys_only=False):
    import yaml
    try:
        doc = yaml.safe_load(open(path, encoding="utf-8")) or {}
    except Exception as error:
        problems.append(("yaml", path, "unreadable", str(error)))
        return
    if not isinstance(doc, dict):
        return
    for key, body in doc.items():
        if french(key):
            problems.append(("yaml", path, "key", key))
        if keys_only or not isinstance(body, dict):
            continue
        for inner in body:
            if french(inner):
                problems.append(("yaml", path, "key", "%s.%s" % (key, inner)))
    for arg in doc.get("ARGS") or []:
        name = (arg or {}).get("name") if isinstance(arg, dict) else None
        if name and french(name):
            problems.append(("yaml", path, "arg", name))
    for tag in doc.get("TAGS") or []:
        if french(tag):
            problems.append(("yaml", path, "tag", tag))


def audit_names(problems):
    skip = (".git", "node_modules", "__pycache__", ".hermes")
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in skip]
        for name in names + dirs:
            if name == "LA_Info@moussa":
                continue
            if french(os.path.splitext(name)[0]):
                problems.append(("name", os.path.join(base, name), "name", name))


def harvest():
    raw = set()
    for path in files("config/programs/*.py") + files("config/state/**/*.py"):
        if path.endswith("audit_vocab.py"):
            continue
        try:
            tree = ast.parse(open(path, encoding="utf-8").read())
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            for attr in ("id", "arg", "name", "attr"):
                value = getattr(node, attr, None)
                if isinstance(value, str):
                    raw.add(value)
            for value in getattr(node, "names", []) or []:
                raw.add(value)
    for path in files("config/engine/*.sh"):
        raw.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", open(path, encoding="utf-8").read()))
    for path in files("config/applets/**/*.js"):
        raw.update(re.findall(r"[A-Za-z_$][\w$]*", open(path, encoding="utf-8").read()))
    import yaml
    for path in files("config/*.yaml") + files("config/tools/*/*.yaml"):
        try:
            doc = yaml.safe_load(open(path, encoding="utf-8")) or {}
        except Exception:
            continue
        if isinstance(doc, dict):
            raw.update(str(k) for k in doc)
            for arg in doc.get("ARGS") or []:
                if isinstance(arg, dict) and arg.get("name"):
                    raw.add(str(arg["name"]))
            for tag in doc.get("TAGS") or []:
                raw.add(str(tag))
            for body in doc.values():
                if isinstance(body, dict):
                    raw.update(str(k) for k in body)
    skip = (".git", "node_modules", "__pycache__", ".hermes")
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in skip]
        for name in names + dirs:
            raw.add(os.path.splitext(name)[0])
    return raw


CACHE = os.path.join(ROOT, "config", "state", "vocab_cache.json")
WATCHED = ("config/programs/*.py", "config/state/**/*.py", "config/engine/*.sh",
           "config/applets/**/*.js", "config/*.yaml", "config/tools/*/*.yaml")


def stamp():
    newest = 0.0
    count = 0
    for pattern in WATCHED:
        for path in glob.glob(os.path.join(ROOT, pattern), recursive=True):
            if path.endswith("audit_vocab.py"):
                continue
            try:
                info = os.stat(path)
            except OSError:
                continue
            newest = max(newest, info.st_mtime)
            count += 1
    return "%d:%.6f" % (count, newest)


def cached_rows(key):
    try:
        with open(CACHE, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    if data.get("key") != key:
        return None
    return [tuple(row) for row in data.get("rows", [])]


def store_rows(key, rows):
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w", encoding="utf-8") as handle:
            json.dump({"key": key, "rows": [list(row) for row in rows]}, handle, ensure_ascii=False)
    except OSError:
        pass


def main():
    key = stamp()
    rows = None if "--fresh" in sys.argv else cached_rows(key)
    if rows is None:
        build_oracle(harvest())
        rows = sorted({(kind, os.path.relpath(path, ROOT), what, name)
                       for kind, path, what, name in collect_problems()})
        store_rows(key, rows)
    if "--json" in sys.argv:
        print(json.dumps(rows, ensure_ascii=False))
        return 0 if not rows else 1
    for kind, path, what, name in rows:
        print("%-10s %-46s %-10s %s" % (kind, path, what, name))
    print("total: %d" % len(rows))
    return 0 if not rows else 1


def collect_problems():
    problems = []
    for path in files("config/programs/*.py"):
        if not path.endswith("audit_vocab.py"):
            audit_python(path, problems)
    for path in files("config/state/**/*.py"):
        audit_python(path, problems)
    for path in files("config/engine/*.sh"):
        audit_shell(path, problems)
    for path in files("config/applets/**/*.js"):
        audit_js(path, problems)
    for path in files("config/*.yaml"):
        audit_yaml(path, problems, keys_only=path.endswith("messages.yaml"))
    for path in files("config/tools/*/*.yaml"):
        audit_yaml(path, problems)
    audit_names(problems)
    return problems


if __name__ == "__main__":
    sys.exit(main())
