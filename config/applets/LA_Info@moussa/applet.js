// LA_Info -- les mesures de LA dans le panneau, dessinees avec St, le Shell Toolkit de Cinnamon.
//
// UNE SEULE SOURCE : le tableau de LA (config/engine/board.sh). Il rend une ligne par mesure, au
// format etat|section|titre|verdict. On ne lit rien d'autre et on ne demande rien a personne : le
// tableau est l'instrument, et il est le seul.
//
// La lecture passe par Gio.Subprocess, qui rend la sortie MEME QUAND le code de sortie est mauvais --
// et il l'est des qu'une mesure est en faute, c'est son role. On ne depend donc jamais du code de
// sortie. Un garde-fou de dix secondes coupe le tableau s'il s'endort, pour ne jamais figer la barre.

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Mainloop = imports.mainloop;
const Settings = imports.ui.settings;
const St = imports.gi.St;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const Clutter = imports.gi.Clutter;

const DOSSIER_ICONES = GLib.get_home_dir() + "/.local/share/cinnamon/applets/LA_Info@moussa/icons";

// L'etat d'une mesure dit de quelle pastille elle s'habille.
const PASTILLE = { ok: "la-actif.svg", ko: "la-disabled.svg" };

// Ce que la barre montre en permanence : les mesures qui bougent vraiment.
const EN_BARRE = ["residents", "ram de LA"];

// Un emoticone par mesure : il dit le sujet, la pastille dit l'etat.
const EMOTICONE = {
    "LA status": "\u{1F7E2}",
    "residents": "\u{1F465}",
    "ram de LA": "\u{1F9E0}",
    "sessions": "\u{1F4AC}",
    "last_activity": "\u{23F1}",
    "engine": "\u{2699}",
    "table": "\u{1F4CB}",
    "canon": "\u{1F4D6}",
    "git": "\u{1F33F}",
    "doctor": "\u{1FA7A}",
    "erreurs": "\u{1F41E}",
    "journal": "\u{1F4D3}",
    "api": "\u{1F50C}",
    "endpoint": "\u{1F310}",
    "api status": "\u{1F4E1}",
    "pont": "\u{1F309}",
    "vision": "\u{1F441}",
};

// Une barre n'a de sens que sur une mesure qui porte un rapport. On le lit dans le verdict :
// "5/5 actifs", "123/123", "25 ok / 0 defaut". Pas de rapport, pas de barre.
function rapportDe(verdict) {
    let m = verdict.match(/(\d+)\s*ok\s*\/\s*(\d+)\s*defaut/);
    if (m) { const a = Number(m[1]), b = Number(m[2]); return (a + b) > 0 ? a / (a + b) : 0; }
    m = verdict.match(/(\d+)\s*\/\s*(\d+)/);
    if (m) { const a = Number(m[1]), b = Number(m[2]); return b > 0 ? Math.min(a / b, 1) : 0; }
    return null;
}

const LARGEUR_BARRE = 72;

function emoticoneDe(titre) {
    return EMOTICONE[titre] || "\u2022";
}

class LAInfoApplet extends Applet.TextIconApplet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        super(orientation, panelHeight, instanceId);

        this._pret = false;
        this._lignes = [];
        this._quand = null;
        this._minuterie = 0;
        this._enLecture = false;
        this.setAllowedLayout(Applet.AllowedLayout.BOTH);

        this._reglages = new Settings.AppletSettings(this, metadata.uuid, instanceId);
        // bind, pas bindProperty : bindProperty attend la direction en premier argument, et lui passer
        // la cle a la place envoie la fonction de retour dans la case du nom de propriete.
        this._reglages.bind("tableau", "tableau", () => { if (this._pret) { this._lire(); } });
        this._reglages.bind("secondes", "secondes", () => { if (this._pret) { this._remonterLaMontre(); } });

        // LE MENU : dessine par nous, avec St.
        this._menu = new Applet.AppletPopupMenu(this, orientation);
        this._gestion = new PopupMenu.PopupMenuManager(this);
        this._gestion.addMenu(this._menu);

        this._peindre();
        this._pret = true;
        this._lire();
        this._remonterLaMontre();
    }

    // ---- la montre : le tableau est relu toutes les N secondes, et il ne s'arrete pas
    _remonterLaMontre() {
        if (this._minuterie) { Mainloop.source_remove(this._minuterie); }
        this._minuterie = Mainloop.timeout_add_seconds(this.secondes || 10, () => {
            this._lire();
            return true;
        });
    }

    // ---- la lecture
    _lire() {
        if (this._enLecture || !this.tableau) { return; }
        this._enLecture = true;

        let proc;
        try {
            proc = Gio.Subprocess.new([this.tableau, "--menu"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch (e) {
            this._enLecture = false;
            global.logError("LA_Info : le tableau n'a pas pu etre lance : " + e.message);
            return;
        }

        let fini = false;
        const garde = Mainloop.timeout_add_seconds(10, () => {
            if (!fini) { try { proc.force_exit(); } catch (e) { } }
            return false;
        });

        proc.communicate_utf8_async(null, null, (p, res) => {
            fini = true;
            this._enLecture = false;
            try { Mainloop.source_remove(garde); } catch (e) { }

            const lignes = [];
            try {
                const texte = p.communicate_utf8_finish(res)[1] || "";
                texte.split("\n").forEach((l) => {
                    if (l.indexOf("|") === -1) { return; }
                    const c = l.split("|");
                    lignes.push({ etat: c[0], section: c[1], titre: c[2], verdict: c.slice(3).join("|") });
                });
            } catch (e) { }

            this._lignes = lignes;
            this._quand = new Date();
            this._peindre();
            this._dessinerLeMenu();
        });
    }

    // ---- ce qui se voit sans rien ouvrir : la pastille de l'etat, et deux chiffres qui bougent
    _peindre() {
        if (this._lignes.length === 0) {
            this.set_applet_icon_path(DOSSIER_ICONES + "/la-inconnu.svg");
            this.set_applet_label("?");
            this.set_applet_tooltip("le tableau n'a rien rendu");
            return;
        }

        const etat = this._lignes[0].etat;
        this.set_applet_icon_path(DOSSIER_ICONES + "/" + (PASTILLE[etat] || PASTILLE.ko));

        const courts = [];
        this._lignes.forEach((l) => {
            if (EN_BARRE.indexOf(l.titre) > -1) { courts.push(emoticoneDe(l.titre) + " " + l.verdict); }
        });
        this.set_applet_label(courts.join("  "));

        const heure = this._quand ? this._quand.toLocaleTimeString() : "";
        this.set_applet_tooltip(this._lignes.map((l) => l.titre + " : " + l.verdict).join("\n")
            + (heure ? "\n\nrelu a " + heure : ""));
    }

    // ---- MES RANGEES, EN ST, SANS PASSER PAR PopupMenuItem
    //
    // PopupMenuItem fabrique des colonnes dont la largeur est partagee entre TOUTES les lignes
    // du menu : le libelle de la ligne « Relire le tableau » imposait 184 px de vide au debut de
    // chacune des miennes, d ou ce contenu tasse vers la droite. Ses rangees sont donc a moi.
    _rangee(enfants, classe) {
        const rangee = new St.BoxLayout({ style_class: classe || "la-info-rangee" });
        rangee.x_expand = true;
        enfants.forEach((e) => rangee.add_child(e));
        return rangee;
    }

    _petitLabel(texte, classe) {
        return new St.Label({ text: texte, style_class: classe, x_align: Clutter.ActorAlign.START });
    }

    _ligneDeMenu(ligne) {
        const enfants = [];
        enfants.push(new St.Icon({
            gicon: Gio.icon_new_for_string(DOSSIER_ICONES + "/" + (PASTILLE[ligne.etat] || PASTILLE.ko)),
            icon_size: 12,
        }));
        enfants.push(this._petitLabel(ligne.titre, "la-info-titre"));
        enfants.push(this._petitLabel(emoticoneDe(ligne.titre), "la-info-emoticone"));
        const fraction = rapportDe(ligne.verdict);
        enfants.push(fraction === null ? new St.Widget({ style_class: "la-info-slot" }) : this._barre(fraction));
        enfants.push(this._petitLabel(ligne.verdict, "la-info-verdict"));
        return this._rangee(enfants);
    }

    // La barre : un rail de largeur fixe, et dedans la part pleine.
    _barre(fraction) {
        const rail = new St.Bin({ style_class: "la-info-rail" });
        rail.set_width(72);
        rail.set_child(new St.Widget({
            style_class: fraction >= 1 ? "la-info-plein" : "la-info-partiel",
            width: Math.max(2, Math.round(72 * fraction)),
        }));
        return rail;
    }

    _dessinerLeMenu() {
        this._menu.removeAll();

        // Mes rangees a moi : je les detruis moi-meme, removeAll ne connait que les items.
        if (this._mesRangees) {
            this._mesRangees.forEach((r) => { try { r.destroy(); } catch (e) { } });
        }
        this._mesRangees = [];

        const quand = this._quand ? this._quand.toLocaleTimeString() : "jamais";
        const tete = this._rangee([this._petitLabel("LA_Info", "la-info-tete")]);
        const heure = this._rangee([this._petitLabel("mesures relues a " + quand, "la-info-quand")]);
        [tete, heure].forEach((r) => { this._menu.box.add_child(r); this._mesRangees.push(r); });

        let section = null;
        this._lignes.forEach((l) => {
            if (l.section !== section) {
                section = l.section;
                const titre = this._rangee([this._petitLabel(section, "la-info-section")]);
                this._menu.box.add_child(titre);
                this._mesRangees.push(titre);
            }
            const ligne = this._ligneDeMenu(l);
            this._menu.box.add_child(ligne);
            this._mesRangees.push(ligne);
        });

        // Une seule vraie entree de menu, tout en bas : elle seule a le droit d etre cliquee,
        // et tant qu il n y en a qu une, ses colonnes ne genent personne.
        const rafraichir = new PopupMenu.PopupMenuItem("\u21bb  Relire le tableau, maintenant");
        rafraichir.connect("activate", () => { this._lire(); });
        this._menu.addMenuItem(rafraichir);
    }

    on_applet_clicked(event) {
        this._menu.toggle();
    }

    on_applet_middle_clicked(event) {
        this._lire();
    }

    on_applet_removed_from_panel() {
        if (this._minuterie) { Mainloop.source_remove(this._minuterie); this._minuterie = 0; }
        try { this._reglages.finalize(); } catch (e) { }
    }
}

function main(metadata, orientation, panelHeight, instanceId) {
    return new LAInfoApplet(metadata, orientation, panelHeight, instanceId);
}
