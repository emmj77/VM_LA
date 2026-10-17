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

    // ---- une ligne du menu, montee avec St. Le conteneur d'un PopupMenuItem n'est pas un
    // St.BoxLayout : c'est un Cinnamon.GenericContainer, dont la mise en page se donne a addActor
    // sous la forme {span, expand, align}. C'est l'idiome du code de Cinnamon lui-meme.
    _ligneDeMenu(ligne) {
        const item = new PopupMenu.PopupMenuItem("");
        item.addActor(new St.Icon({
            gicon: Gio.icon_new_for_string(DOSSIER_ICONES + "/" + (PASTILLE[ligne.etat] || PASTILLE.ko)),
            icon_size: 12,
        }), { span: 0 });
        item.addActor(new St.Label({ text: emoticoneDe(ligne.titre), style_class: "la-info-emoticone" }), { span: 0 });
        item.addActor(new St.Label({ text: ligne.titre, style_class: "la-info-titre" }));
        // TOUT A GAUCHE : le verdict suit le titre, il n'est plus pousse contre le bord droit.
        item.addActor(new St.Label({ text: ligne.verdict, style_class: "la-info-verdict" }));
        return item;
    }

    _titreDeMenu(texte, classe) {
        const item = new PopupMenu.PopupMenuItem("");
        item.actor.reactive = false;
        item.addActor(new St.Label({ text: texte, style_class: classe }), { span: -1, expand: true });
        return item;
    }

    _dessinerLeMenu() {
        this._menu.removeAll();

        const quand = this._quand ? this._quand.toLocaleTimeString() : "jamais";
        this._menu.addMenuItem(this._titreDeMenu("LA_Info", "la-info-tete"));
        this._menu.addMenuItem(this._titreDeMenu("mesures relues a " + quand, "la-info-quand"));
        this._menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        let section = null;
        this._lignes.forEach((l) => {
            if (l.section !== section) {
                section = l.section;
                this._menu.addMenuItem(this._titreDeMenu(section, "la-info-section"));
            }
            this._menu.addMenuItem(this._ligneDeMenu(l));
        });

        this._menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        const rafraichir = new PopupMenu.PopupMenuItem("Relire le tableau, maintenant");
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
