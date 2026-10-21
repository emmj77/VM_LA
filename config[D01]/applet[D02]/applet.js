// id: G01
// LA_Info -- les mesures de LA dans le panneau, dessinees avec St, le Shell Toolkit de Cinnamon.
//
// UNE SEULE SOURCE : le board de LA (config/engine/board.sh). Il rend une line par mesure, au
// format state|section|title|verdict. On ne lit rien d'autre et on ne demande rien a personne : le
// board est l'instrument, et il est le seul.
//
// La lecture passe par Gio.Subprocess, qui rend la sortie MEME QUAND le code de sortie est mauvais --
// et il l'est des qu'une mesure est en faute, c'est son role. On ne depend donc jamais du code de
// sortie. Un guard-fou de dix secondes coupe le board s'il s'endort, pour ne jamais figer la barre.

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Mainloop = imports.mainloop;
const Settings = imports.ui.settings;
const St = imports.gi.St;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const Clutter = imports.gi.Clutter;

const RESIDENT_NAMES = ["models", "asr", "tts"];
const DOT_WIDTH = 18;
const TITLE_WIDTH = 150;
const EMO_WIDTH = 22;
const ICON_DIR = GLib.get_home_dir() + "/.local/share/cinnamon/applets/LA_Info@moussa/icons";
const CACHE = GLib.get_home_dir() + "/.cache/la_info_menu.txt";

// L'state d'une mesure dit de quelle pastille elle s'habille.
const BADGE = { ok: "la-active.svg", ko: "la-disabled.svg" };

// Ce que la barre montre en permanence : les mesures qui bougent vraiment.
const IN_BAR = ["residents", "ram of LA"];

// Un emoticone par mesure : il dit le sujet, la pastille dit l'state.
const EMOTICONE = {
    "LA status": "\u{1F7E2}",
    "residents": "\u{1F465}",
    "models": "\u{1F9E9}",
    "asr": "\u{1F3A4}",
    "tts": "\u{1F50A}",
    "dash": "\u{1F4CA}",
    "tesseract": "\u{1F527}",
    "ram of LA": "\u{1F9E0}",
    "sessions": "\u{1F4AC}",
    "last_activity": "\u{23F1}",
    "engine": "\u{2699}",
    "table": "\u{1F4CB}",
    "canon": "\u{1F4D6}",
    "git": "\u{1F33F}",
    "doctor": "\u{1FA7A}",
    "errors": "\u{1F41E}",
    "journal": "\u{1F4D3}",
    "api": "\u{1F50C}",
    "endpoint": "\u{1F310}",
    "api status": "\u{1F4E1}",
    "bridge": "\u{1F309}",
    "vision": "\u{1F441}",
    // une line par carte, comme pour les residents
    "gpu RTX 3060": "\u{1F3AE}",
    "gpu Quadro P2200": "\u{1F5A5}",
    // les cinq residents, un par line maintenant
    "resident embed": "\u{1F9E9}",
    "resident rerank": "\u{1F3AF}",
    "resident local": "\u{270D}",
    "resident asr": "\u{1F442}",
    "resident tts": "\u{1F5E3}",
};

// Une barre n'a de sens que sur une mesure qui porte un rapport. On le lit dans le verdict :
// "5/5 actifs", "123/123", "25 ok / 0 defaut". Pas de rapport, pas de barre.
// LA PART D UNE MESURE, ET SON GENRE.
//
// Deux genres, parce qu elles ne veulent pas dire la meme chose :
//   * "health" : une share qui doit valoir 100 pour cent. En dessous, c est une faute, et l ambre
//     le dit. residents 5/5, table 123/123, doctor 25 ok / 0 defaut, journal 0 echec.
//   * "share"  : une consommation. Zero n est pas un defaut et cent n en est pas un non plus. La
//     couleur est alors une chaleur, pas une sanction : vert tranquille, ambre si le resident
//     mange la moitie de la memoire de LA, rouge au dela.
//
// Un resident donne sa memoire en Mo (701 Mo) : sa share se lit contre la line "ram of LA", qui
// donne le total. C est la seule facon honnete de faire une barre de memoire -- il faut un tout.
function ratioOf(title, verdict, ramDeLA) {
    let m = verdict.match(/(\d+)\s*ok\s*\/\s*(\d+)\s*fault/);
    if (m) { const a = Number(m[1]), b = Number(m[2]); return { share: (a + b) > 0 ? a / (a + b) : 0, kind: "health" }; }
    // LA MACHINE EN FACE : « 1430 Mo / 46 Go ». La barre dit la share de la machine prise par LA.
    if (title === "ram of LA") {
        m = verdict.match(/(\d+)\s*MB\s*\/\s*(\d+)\s*GB/);
        if (m) { const mo = Number(m[1]), go = Number(m[2]); return { share: go > 0 ? Math.min(mo / 1024 / go, 1) : 0, kind: "share" } }
    }
    // UNE BARRE SEULEMENT POUR CE QUI SE MESURE : les quatre totaux (residents, ram, les deux
    // cartes). Un resident, un instrument, un outil : leur etat suffit, pas de rail. MOUSSA, 21/10 :
    // « les champs avec des barres restent comme ca », donc on n en ajoute pas aux autres.
    if (title === "tesseract" || title === "vision") {
        return null;
    }
    if (RESIDENT_NAMES.indexOf(title) > -1) {
        return null;
    }
    // UNE CARTE SE MESURE CONTRE ELLE-MEME : « 9 / 12288 Mo » est ce qu elle a pris sur ce
    // qu elle peut prendre. Genre « share » et non « health » : c est une consommation, elle
    // chauffe (vert sous la moitie, ambre a la moitie, rouge au dela), elle ne sanctionne pas.
    if (title.startsWith("gpu ")) {
        m = verdict.match(/^(\d+)\s*\/\s*(\d+)/);
        if (m) { const a = Number(m[1]), b = Number(m[2]); return { share: b > 0 ? Math.min(a / b, 1) : 0, kind: "share" }; }
    }
    m = verdict.match(/(\d+)\s*\/\s*(\d+)\b/);
    if (m) { const a = Number(m[1]), b = Number(m[2]); return { share: b > 0 ? Math.min(a / b, 1) : 0, kind: "health" }; }
    if (title === "journal") {
        m = verdict.match(/(\d+)\s*failed/);
        if (m) return { share: Number(m[1]) === 0 ? 1 : 0.25, kind: "health" };
    }
    if (title === "errors") {
        m = verdict.match(/^(\d+)/);
        if (m) return { share: Number(m[1]) === 0 ? 1 : 0.25, kind: "health" };
    }
    return null;
}

const BAR_WIDTH = 72;

function parseRows(text) {
    const rows = [];
    text.split("\n").forEach((l) => {
        if (l.indexOf("|") === -1) { return; }
        const c = l.split("|");
        rows.push({ state: c[0], section: c[1], title: c[2], verdict: c.slice(3).join("|") });
    });
    // LA LIGNE DU CLI : elle ferme la section LA, sans deplacer une seule rangee existante
    let at = -1;
    rows.forEach((r, i) => { if (r.section === "LA") { at = i; } });
    rows.splice(at + 1, 0, { state: "ok", section: "LA", title: "cli", verdict: "board.py --cli" });
    return rows;
}

function iconOf(title) {
    return EMOTICONE[title] || "\u2022";
}

class LAInfoApplet extends Applet.TextIconApplet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        super(orientation, panelHeight, instanceId);

        this._ready = false;
        this._lines = [];
        this._when = null;
        this._timer = 0;
        this._reading = false;
        this.setAllowedLayout(Applet.AllowedLayout.BOTH);

        this._settings = new Settings.AppletSettings(this, metadata.uuid, instanceId);
        // bind, pas bindProperty : bindProperty attend la direction en premier argument, et lui passer
        // la cle a la place envoie la fonction de retour dans la case du nom de propriete.
        this._settings.bind("board", "board", () => { if (this._ready) { this._read(); } });
        this._settings.bind("seconds", "seconds", () => { if (this._ready) { this._restartWatch(); } });

        // LE MENU : dessine par nous, avec St.
        this._menu = new Applet.AppletPopupMenu(this, orientation);
        this._manage = new PopupMenu.PopupMenuManager(this);
        this._manage.addMenu(this._menu);

        this._lines = this._rowsFromCache();
        this._paint();
        this._ready = true;
        this._read();
        this._restartWatch();
    }

    // ---- la montre : le board est relu toutes les N secondes, et il ne s'arrete pas
    _rowsFromCache() {
        try {
            const [, bytes] = GLib.file_get_contents(CACHE);
            return parseRows(bytes.toString());
        } catch (e) {
            return [];
        }
    }

    _restartWatch() {
        if (this._timer) { Mainloop.source_remove(this._timer); }
        this._timer = Mainloop.timeout_add_seconds(this.secondes || 15, () => {
            this._read();
            return true;
        });
    }

    // ---- la lecture
    // board.py vit a cote de la porte : la porte est dans config[D01]/engine[D07]/la.sh
    _cliPath() {
        const engine = GLib.path_get_dirname(this.board);      // engine[D07]
        const conf = GLib.path_get_dirname(engine);            // config[D01]
        return GLib.build_filenamev([conf, "programs[D10]", "board.py"]);
    }

    _read() {
        if (this._reading || !this.board) { return; }
        this._reading = true;

        let proc;
        try {
            // LA TABLE EST board.py : un seul tableau, le sien. On le lance, on ne le double pas.
            proc = Gio.Subprocess.new(["python3", this._cliPath(), "--menu"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch (e) {
            this._reading = false;
            global.logError("LA_Info : le board n'a pas pu etre lance : " + e.message);
            return;
        }

        let done = false;
        const guard = Mainloop.timeout_add_seconds(30, () => {
            if (!done) { try { proc.force_exit(); } catch (e) { } }
            return false;
        });

        proc.communicate_utf8_async(null, null, (p, res) => {
            done = true;
            this._reading = false;
            try { Mainloop.source_remove(guard); } catch (e) { }

            const rows = [];
            let text = "";
            try {
                text = p.communicate_utf8_finish(res)[1] || "";
            } catch (e) { text = ""; }
            parseRows(text).forEach((r) => rows.push(r));

            if (rows.length === 0 && this._lines.length > 0) {
                this._stale = true;
                this._paint();
                return;
            }

            if (rows.length > 0) {
                this._stale = false;
                try { GLib.file_set_contents(CACHE, text); } catch (e) { }
            }
            this._lines = rows;
            // L'APPROBATION SE LIT DANS LES LIGNES DU TABLEAU, pas dans un second appel : la line
            // dont le title est « approbation » porte le geste en clair (tool + geste). S'il n'y en
            // a pas, il n'y a rien a approve et le bouton n'existe pas.
            this._approval = null;
            rows.forEach((l) => {
                if (l.title !== "approbation" || this._approval) { return; }
                // LE GESTE EST FACULTATIF : un tool sans action (download_file, install_program)
                // s ecrit « download_file » -- avec la regex a DEUX mots obligatoires, le bouton
                // n apparaissait pas pour ces gestes-la, qui sont justement ceux a signer.
                const m = l.verdict.match(/^([a-z_][a-z0-9_]*)(?: +([a-z_][a-z0-9_:]*))?/);
                if (m) { this._approval = [m[1], m[2] || ""]; }
            });
            this._when = new Date();
            this._paint();
            this._dessinerLeMenu();
        });
    }

    // ---- ce qui se voit sans rien ouvrir : la pastille de l'state, et deux chiffres qui bougent
    _paint() {
        if (this._lines.length === 0) {
            this.set_applet_icon_path(ICON_DIR + "/la-unknown.svg");
            this.set_applet_label("?");
            this.set_applet_tooltip("le board n'a rien rendu");
            return;
        }

        // PAS DE ROND ROUGE DANS LE PANNEAU (MOUSSA, 21/10) : le panneau porte les chiffres,
        // ce sont les pastilles du menu qui disent quelle ligne va mal.
        this.set_applet_icon_path(ICON_DIR + "/" + BADGE.ok);

        const courts = [];
        this._lines.forEach((l) => {
            if (IN_BAR.indexOf(l.title) > -1) { courts.push(iconOf(l.title) + " " + l.verdict); }
        });
        this.set_applet_label(courts.join("  "));

        const hour = this._when ? this._when.toLocaleTimeString() : "";
        this.set_applet_tooltip(this._lines.map((l) => l.title + " : " + l.verdict).join("\n")
            + (hour ? "\n\nrelu a " + hour : ""));
    }

    // ---- MES RANGEES, EN ST, SANS PASSER PAR PopupMenuItem
    //
    // PopupMenuItem fabrique des colonnes dont la largeur est partagee entre TOUTES les lignes
    // du menu : le libelle de la line « Relire le board » imposait 184 px de vide au debut de
    // chacune des miennes, d ou ce contenu tasse vers la droite. Ses rangees sont donc a moi.
    _rangee(children, klass) {
        const row = new St.BoxLayout({ style_class: klass || "la-info-row" });
        row.x_expand = true;
        children.forEach((e) => row.add_child(e));
        return row;
    }

    _smallLabel(text, klass, width, align) {
        const l = new St.Label({ text: text, style_class: klass,
                                 x_align: align || Clutter.ActorAlign.START });
        if (width) { l.set_width(width); l.clutter_text.ellipsize = 3; }
        else if (align === Clutter.ActorAlign.END) { l.x_expand = true; }
        return l;
    }

    _ligneDeMenu(line) {
        const children = [];
        // MEME DEPART POUR TOUTES LES BARRES : un title plus long poussait le rail a droite.
        // LA GAUCHE EN MAJUSCULES (MOUSSA, 19/10), la droite collee au bord.
        // L EMOTICONE DANS LA COLONNE DE GAUCHE (MOUSSA, 19/10), a la place des pastilles : la
        // line commence par son signe, puis son nom. Les pastilles vertes ne bougeaient pas -- il
        // avait raison, elles ne disaient rien.
        // QUATRE COLONNES : le signe, le nom, la pastille, la mesure, le verdict (MOUSSA, 21/10).
        // La pastille revient en deuxieme position, dans une colonne fine : toutes les pastilles
        // tombent sur la meme abscisse, quel que soit le nom.
        children.push(this._smallLabel(iconOf(line.title), "la-info-emoji", EMO_WIDTH));
        children.push(this._smallLabel(line.title.toUpperCase(), "la-info-title", TITLE_WIDTH));
        children.push(this._pastille(line));
        const r = ratioOf(line.title, line.verdict, this._ramOfLA);
        children.push(r !== null ? this._barre(r) : this._slotVide());
        children.push(this._smallLabel(line.verdict, "la-info-verdict", 0, Clutter.ActorAlign.END));
        return this._rangee(children);
    }

    // La couleur d une barre : la health sanctionne (vert si parfait, ambre sinon), la
    // consommation chauffe (vert sous la moitie, ambre a la moitie, rouge au dela).
    _couleurDe(r) {
        if (r.kind === "health") return r.share >= 1 ? "la-info-full" : "la-info-partial";
        if (r.share >= 0.8) return "la-info-hot";
        if (r.share >= 0.5) return "la-info-partial";
        return "la-info-full";
    }

    // UNE BADGE QUAND IL N Y A RIEN A MESURER (MOUSSA, 19/10 : « vert si good, gris si
    // decharge, rouge si souci »). Un carre de 9 px, a la meme place que le rail : les lignes
    // gardent leur colonne, et l oeil lit trois etats sans lire un chiffre.
    // LES LIGNES SANS BARRE ONT LEUR BADGE, au CENTRE du meme emplacement : vert si tout va
    // bien, gris si c est muet ou decharge, rouge si c est en faute. Plus courte qu une barre
    // (11 x 6 contre 72 x 7) : l oeil ne confond pas un state avec une mesure.
    // la colonne de la mesure quand il n y en a pas : meme largeur, donc le verdict reste aligne
    _slotVide() {
        const box = new St.BoxLayout({ style_class: "la-info-slot" });
        box.set_width(BAR_WIDTH);
        box.add_child(new St.Widget({ x_expand: true }));
        return box;
    }

    _pastille(line) {
        let klass = "la-info-green";
        if (line.state === "note") klass = "la-info-grey";
        else if (line.state !== "ok") klass = "la-info-red";
        else if (/muet|decharge|absent|eteint|non charge|\b0 Mo\b/i.test(line.verdict)) klass = "la-info-grey";
        const box = new St.BoxLayout({ style_class: "la-info-slot" });
        box.set_width(DOT_WIDTH);
        box.add_child(new St.Widget({ x_expand: true }));
        // LA PASTILLE D AVANT, DANS LA COLONNE D AUJOURD HUI (MOUSSA, 21/10) : le signe vert ou
        // rouge du projet, centre dans une colonne de largeur fixe, donc tous alignes.
        const dot = new St.Icon({
            gicon: Gio.icon_new_for_string(ICON_DIR + "/" + (BADGE[line.state] || BADGE.ko)),
            icon_size: 12,
            y_align: Clutter.ActorAlign.CENTER,
        });
        box.add_child(dot);
        box.add_child(new St.Widget({ x_expand: true }));
        return box;
    }

    _barre(r) {
        // UNE BOITE, PAS UN St.Bin. Mesure du 17/10 : sur un rail de 72 px, un remplissage de
        // 9 px se posait a x=31 -- soit exactement (72-9)/2, le centre. St.Bin centrait son
        // enfant et x_align n y changeait rien. Une box horizontale range ses children de
        // gauche a droite, sans interpretation : le vert share du bord, un ressort mange le reste.
        const rail = new St.BoxLayout({ style_class: "la-info-rail" });
        rail.set_width(72);
        // ZERO N EST PAS DEUX PIXELS : un rail a 0 Mo reste VIDE, sinon il ment.
        const filled = Math.round(72 * r.share);
        if (filled > 0) {
            rail.add_child(new St.Widget({ style_class: this._couleurDe(r), width: filled }));
        }
        rail.add_child(new St.Widget({ x_expand: true }));   // le ressort : rien apres le vert
        return rail;
    }

    _dessinerLeMenu() {
        this._menu.removeAll();

        // Mes rangees a moi : je les detruis moi-meme, removeAll ne connait que les items.
        if (this._mesRangees) {
            this._mesRangees.forEach((r) => { try { r.destroy(); } catch (e) { } });
        }
        this._mesRangees = [];

        const when = this._when ? this._when.toLocaleTimeString() : "jamais";
        const head = this._rangee([this._smallLabel("LA_Info", "la-info-head")]);
        const hour = this._rangee([this._smallLabel("mesures relues a " + when, "la-info-when")]);
        [head, hour].forEach((r) => { this._menu.box.add_child(r); this._mesRangees.push(r); });

        // LE TOUT, AVANT LES PARTIES : la line "ram of LA" donne la memoire totale des
        // residents, et c est contre elle que chacun donne sa share. Sans elle, pas de barre.
        this._ramOfLA = 0;
        this._lines.forEach((l) => {
            if (l.title === "ram of LA") {
                const m = l.verdict.match(/(\d+)/);
                if (m) this._ramOfLA = Number(m[1]);
            }
        });

        // DEUX BLOCS : les etats d abord, les mesures ensemble a la fin (MOUSSA, 21/10).
        // Une rangee qui a un rail est une mesure ; les autres disent un etat, et leur couleur
        // suffit : ni carre, ni pastille.
        const estMesure = (l) => ratioOf(l.title, l.verdict, this._ramOfLA) !== null;
        const etats = this._lines.filter((l) => !estMesure(l));
        const mesures = this._lines.filter((l) => estMesure(l));

        let section = null;
        const poser = (l) => {
            if (l.section !== section) {
                section = l.section;
                const t = this._rangee([this._smallLabel(section, "la-info-section")]);
                this._menu.box.add_child(t);
                this._mesRangees.push(t);
            }
            const line = this._ligneDeMenu(l);
            this._menu.box.add_child(line);
            this._mesRangees.push(line);
        };
        etats.forEach(poser);
        if (mesures.length) {
            section = "MESURES";
            const t = this._rangee([this._smallLabel("MESURES", "la-info-section")]);
            this._menu.box.add_child(t);
            this._mesRangees.push(t);
            mesures.forEach((l) => {
                const line = this._ligneDeMenu(l);
                this._menu.box.add_child(line);
                this._mesRangees.push(line);
            });
        }

        // L'APPROBATION, ET ELLE SEULE A UN BOUTON. C'est le seul geste du harnais qui ATTEND un
        // humain : une demande ecrite par la boucle (work/approve.request) que personne n'a encore
        // signee. Le clic appelle approval.sh allow <tool> <geste> : il ne fait rien d'autre, il
        // n'ecrit pas le feu vert lui-meme -- la porte reste une seule, celle du projet.
        if (this._approval) {
            const [outil, geste] = this._approval;
            const approve = new PopupMenu.PopupMenuItem(
                "\u2713  Approuver " + outil + " " + geste + " (une fois)");
            approve.connect("activate", () => { this._approve(outil, geste); });
            this._menu.addMenuItem(approve);
        }

        // LE CLI S OUVRE ICI : ta table, dans un terminal, telle quelle
        const cli = new PopupMenu.PopupMenuItem("\u2328  Ouvrir le CLI (board.py)");
        cli.connect("activate", () => {
            try {
                Gio.Subprocess.new(["x-terminal-emulator", "-e", "python3", this._cliPath(), "--cli"],
                    Gio.SubprocessFlags.NONE);
            } catch (e) {
                global.logError("LA_Info : le cli ne s ouvre pas : " + e.message);
            }
        });
        this._menu.addMenuItem(cli);

        // LE TUNNEL, DEUX GESTES : ils vivent ici et pas dans la barre, et ils passent par la
        // porte du projet comme tout le reste -- l applet n a jamais de commande a elle.
        const tsUp = new PopupMenu.PopupMenuItem("\u25b2  Tailscale up");
        tsUp.connect("activate", () => { this._tunnel("up"); });
        this._menu.addMenuItem(tsUp);
        const tsDown = new PopupMenu.PopupMenuItem("\u25bc  Tailscale down");
        tsDown.connect("activate", () => { this._tunnel("down"); });
        this._menu.addMenuItem(tsDown);

        // Une seule vraie entree de menu, tout en bas : elle seule a le droit d etre cliquee,
        // et tant qu il n y en a qu une, ses colonnes ne genent personne.
        const rafraichir = new PopupMenu.PopupMenuItem("\u21bb  Relire le board, maintenant");
        rafraichir.connect("activate", () => { this._read(); });
        this._menu.addMenuItem(rafraichir);
    }

    // le tunnel : un geste, une porte, puis on relit le board pour voir l etat
    _tunnel(op) {
        try {
            const proc = Gio.Subprocess.new(["dash", this.board, "engine", "engine.tunnel", "op=" + op],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
            proc.wait_async(null, () => { this._read(); });
        } catch (e) {
            global.logError("tailscale " + op + " : " + e.message);
        }
    }

    // le clic d'approbation : une commande, deux mots, et on relit le board pour voir le resultat
    _approve(outil, geste) {
        // la porte est DANS LE PROJET, a cote du board : on la deduit du chemin du board,
        // jamais d'un second reglage -- deux reglages a tenir ensemble finissent par diverger.
        try {
            // l'approbation passe par la porte du projet, jamais par un second script
            const proc = Gio.Subprocess.new(["dash", this.board, "engine", "engine.approve", "op=allow"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE | Gio.SubprocessFlags.STDIN_PIPE);
            proc.communicate_utf8_async(outil + " " + geste, null, () => {
                try {
                    const [, sortie, erreur] = proc.communicate_utf8_finish(arguments[1]);
                    if (erreur) { global.logError("LA_Info : " + erreur.trim()); }
                    else if (sortie) { global.log("LA_Info : " + sortie.trim()); }
                } catch (e) { }
            });
        } catch (e) {
            global.logError("LA_Info : approbation impossible : " + e.message);
            return;
        }
        Mainloop.timeout_add_seconds(1, () => { this._read(); return false; });
    }

    on_applet_clicked(event) {
        this._menu.toggle();
    }

    on_applet_middle_clicked(event) {
        this._read();
    }

    on_applet_removed_from_panel() {
        if (this._timer) { Mainloop.source_remove(this._timer); this._timer = 0; }
        try { this._settings.finalize(); } catch (e) { }
    }
}

function main(metadata, orientation, panelHeight, instanceId) {
    return new LAInfoApplet(metadata, orientation, panelHeight, instanceId);
}
