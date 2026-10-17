// la-status@moussa : LE BOUTON DE LA DANS LE PANNEAU DE CINNAMON.
//
// IL NE DESSINE RIEN LUI-MEME. Il DEMANDE au tableau (config/engine/board.sh) et il affiche ce
// qu'on lui rend : une ligne courte toutes les trente secondes (`--line`), et la liste de controle
// complete quand on clique (`--check`). Une verite ne s'ecrit qu'une fois : la ou le tableau la
// mesure, le bouton la repete.
//
// IL NE PEUT PAS GELER LE PANNEAU, et c'est la seule chose qui compte ici : la commande part en
// ASYNCHRONE (Util.spawn_async), JAMAIS dans la boucle de Cinnamon, et jamais deux fois en meme
// temps (le garde-fou `enCours`). Un bouton qui attend une commande, c'est un panneau qui gèle.
//
// IL N'INVENTE RIEN : les idiomes sont ceux d'un applet EPROUVE Deja installe sur cette machine
// (temperature@fevimu, ~406 lignes, Cinnamon 6.4) -- la boucle Mainloop.timeout_add, le garde-fou
// du tour precedent, l'etiquette par set_applet_label, le menu rebati a l'ouverture, et le
// nettoyage dans on_applet_removed_from_panel.

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Mainloop = imports.mainloop;
const Util = imports.misc.util;
const Lang = imports.lang;
const GLib = imports.gi.GLib;
const St = imports.gi.St;
const Clutter = imports.gi.Clutter;

const UUID = "la-status@moussa";
const TABLEAU = GLib.get_home_dir() + "/Documents/VM_LA/config/engine/board.sh";
const BOUTON = GLib.get_home_dir() + "/.local/bin/la";
const SECONDES = 30;      // une demande coute ~1 s : on ne la fait pas toutes les secondes
// LE LAYOUT EST CELUI DE L'APPLET METEO (le choix de Moussa) : une ICONE qui dit la condition,
// puis la VALEUR. La meteo fait exactement ca -- TextIconApplet, set_applet_icon_symbolic_name --
// et c'est ce qui la rend lisible dans une barre de 40 pixels. Les trois noms sont VERIFIES dans la
// vraie chaine d'icones du poste (ils se resolvent vers Adwaita) : une icone manquante serait une
// icone invisible, pas une erreur.
// L'ICONE EST UN DESSIN A NOUS, PAS UN GLYPHE DU THEME. La meteo de Moussa a des icones PLEINES et
// colorees ; un symbole au trait d'Adwaita n'a pas la meme forme, et c'est exactement ce qu'il a vu
// (« meme la forme est differente »). Trois pastilles plates, posees depuis le dossier de l'applet.
// Le glyphe symbolique reste en SECOURS : si le fichier manque, l'icone ne disparait pas.
const ICONE = {
    vert: { fichier: "icone-vert.png", secours: "computer-symbolic" },
    rouge: { fichier: "icone-rouge.png", secours: "computer-fail-symbolic" },
    gris: { fichier: "icone-gris.png", secours: "dialog-question-symbolic" }
};
const LARGEUR = "72";     // la largeur des lignes du menu, en colonnes

function LaStatusApplet(metadata, orientation, instance_id) {
    this._init(metadata, orientation, instance_id);
}

LaStatusApplet.prototype = {
    __proto__: Applet.TextIconApplet.prototype,

    _init: function(metadata, orientation, instance_id) {
        Applet.TextIconApplet.prototype._init.call(this, orientation, instance_id);
        this.setAllowedLayout(Applet.AllowedLayout.BOTH);

        // LE MENU : construit par nous, montre par Cinnamon.
        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);

        this.enCours = false;
        this.controle = [];                     // les lignes de la liste, telles que le tableau les rend
        this.ligne = "LA ...";
        this.icone = "";
        this.chemin = metadata.path;             // les dessins de l'applet vivent a cote d'elle
        this.set_applet_label(this.ligne);
        this._poserIcone("gris");                // avant la premiere reponse : la question
        this.set_applet_tooltip("LA — l'etat du harnais");

        this._demanderLigne();
        this.boucle = Mainloop.timeout_add(SECONDES * 1000, () => {
            this._demanderLigne();
            return true;                       // true : la boucle continue
        });
    },

    // -------------------------------------------------------------- CE QU'ON DEMANDE, ET QUAND
    _demanderLigne: function() {
        if (this.enCours) {
            return;                            // la demande precedente n'est pas revenue : je ne l'empile pas
        }
        if (!GLib.file_test(TABLEAU, GLib.FileTest.EXISTS)) {
            // UNE BARRE DE 40 PIXELS N'EST PAS UN JOURNAL : la raison va dans l'infobulle.
            this._poser("LA ?", "gris", "le tableau est introuvable : " + TABLEAU);
            return;
        }
        this.enCours = true;
        try {
            Util.spawn_async([TABLEAU, "--line", "--largeur", LARGEUR],
                             Lang.bind(this, this._rendreLigne));
        } catch (e) {
            this.enCours = false;
            this._poser("LA ?", "gris", "la demande n'est pas partie (spawn_async a jete)");
        }
    },

    _demanderControle: function() {
        try {
            Util.spawn_async([TABLEAU, "--menu"], Lang.bind(this, this._rendreControle));
        } catch (e) {
            this.controle = ["le tableau ne repond pas"];
            if (this.menu.isOpen) {
                this._remplirMenu();
            }
        }
    },

    // ------------------------------------------------------------------------- CE QU'ON EN FAIT
    // LE TABLEAU N'A RIEN RENDU : on ne montre pas l'ancienne valeur comme si elle etait fraiche
    // (ce serait un mensonge), mais on ne la perd pas non plus -- elle passe dans l'infobulle, et
    // l'etiquette dit qu'elle ne sait pas. Un instrument qui ne mesure pas SE TAIT (loi 1557).
    // L'ICONE, POSEE COMME L'ETIQUETTE : seulement quand elle change (une icone re-creee a chaque
    // tour ferait clignoter la barre).
    _poserIcone: function(couleur) {
        let choix = ICONE[couleur] || ICONE.gris;
        let chemin = (this.chemin || "") + "/" + choix.fichier;
        let quoi = GLib.file_test(chemin, GLib.FileTest.EXISTS) ? chemin : choix.secours;
        if (this.icone === quoi) {
            return;                            // re-poser la meme icone ferait clignoter la barre
        }
        try {
            if (quoi === choix.secours) {
                this.set_applet_icon_symbolic_name(quoi);
            } else {
                this.set_applet_icon_path(quoi);
            }
            this.icone = quoi;
        } catch (e) {
            // une icone qui manque n'est pas une raison de tomber : l'etiquette dit deja l'etat
        }
    },

    _poser: function(court, couleur, infobulle) {
        if (this._applet_label.text !== court) {
            this.set_applet_label(court);
        }
        // LA COULEUR. On AJOUTE notre classe, on ne remplace PAS celle du theme : c'est ce qui
        // evite d'abimer la police et la couleur du panneau de Moussa.
        try {
            this._applet_label.remove_style_class_name("la-vert");
            this._applet_label.remove_style_class_name("la-rouge");
            this._applet_label.remove_style_class_name("la-gris");
            this._applet_label.add_style_class_name("la-" + couleur);
        } catch (e) {
            // une couleur n'est pas une raison de tomber
        }
        this._poserIcone(couleur);
        this.set_applet_tooltip(infobulle);
    },

    _rendreLigne: function(sortie) {
        this.enCours = false;
        let l = (sortie || "").toString().replace(/\s+$/, "");
        l = l.split("\n").pop();               // la derniere ligne ecrite est la reponse
        if (!l) {
            this.ligne = "LA ?";
            this._poser("LA ?", "gris", "le tableau n'a rien rendu"
                        + (this.derniere ? " — derniere reponse : " + this.derniere : ""));
            return;
        }
        this.derniere = l;
        this.ligne = l;
        let court = l.split("|")[0].trim();     // « LA clear » : le panneau n'a pas la place pour plus
        this._poser(court, l.indexOf("clear") > -1 ? "vert" : "rouge", l);
        if (this.menu.isOpen) {
            this._remplirMenu();                // ouvert : on remet a jour sous les yeux
        }
    },

    _rendreControle: function(sortie) {
        let brut = (sortie || "").toString().replace(/\s+$/, "");
        this.controle = brut.length ? brut.split("\n") : ["(la liste est vide)"];
        if (this.menu.isOpen) {
            this._remplirMenu();
        }
    },

    _remplirMenu: function() {
        this.menu.removeAll();
        let section = new PopupMenu.PopupMenuSection("LA — la liste de controle");
        if (this.controle.length === 0) {
            section.addMenuItem(new PopupMenu.PopupMenuItem("... la liste arrive"));
        }
        let legendes = new St.BoxLayout({ vertical: true,
                                          style_class: "weather-current-databox-captions" });
        let valeurs = new St.BoxLayout({ vertical: true,
                                         style_class: "weather-current-databox-values" });
        for (let i = 0; i < this.controle.length; i++) {
            // « etat|etiquette|verdict » : LE TABLEAU DIT CE QU'IL A MESURE, LE MENU LE POSE COMME
            // CINNAMON POSE SES PROPRES MENUS -- la mesure a gauche, la valeur a DROITE, alignee
            // (item.setStatus). C'est la mise en page de l'applet meteo, celle que Moussa designe :
            // « la difference est le jour et la nuit ». Seules les FAUTES sont colorees.
            let champs = this.controle[i].split("|");
            if (champs.length < 3) {
                continue;
            }
            // UNE COLONNE DE LEGENDES ET UNE COLONNE DE VALEURS, COMME LA METEO : ses legendes sont
            // alignees a droite, grisees, et posees a 5 px des valeurs (weather-current-databox-
            // captions). C'est ce couple qui fait la mise en page, et c'est son code, pas le mien.
            let nom = new St.Label({ text: champs[1], x_align: Clutter.ActorAlign.END });
            let val = new St.Label({ text: champs[2] });
            if (champs[0] === "ko") {
                nom.add_style_class_name("la-rouge");
                val.add_style_class_name("la-rouge");
            }
            legendes.add(nom);
            valeurs.add(val);
        }
        let boite = new St.BoxLayout({ style_class: "weather-current-databox" });
        boite.add(legendes);
        boite.add(valeurs);
        // UN BLOC, PAS HUIT LIGNES CLIQUABLES : la meteo pose tout son releve dans un seul item, et
        // c'est pour ca que le survol ne clignote pas d'une ligne a l'autre.
        let bloc = new PopupMenu.PopupBaseMenuItem({ reactive: false });
        bloc.addActor(boite, { span: -1, expand: true });
        section.addMenuItem(bloc);
        this.menu.addMenuItem(section);

        let actions = new PopupMenu.PopupMenuSection();
        let tableau = new PopupMenu.PopupMenuItem("Ouvrir le tableau dans un terminal");
        tableau.connect("activate", Lang.bind(this, function () {
            try {
                Util.trySpawn(["kitty", "--hold", "-e", TABLEAU, "--once"]);
            } catch (e) {
                Util.trySpawn(["sh", "-c", TABLEAU + " --once | less -R"]);
            }
        }));
        actions.addMenuItem(tableau);

        let rafraichir = new PopupMenu.PopupMenuItem("Rafraichir");
        rafraichir.connect("activate", Lang.bind(this, function () {
            this._demanderLigne();
            this._demanderControle();
        }));
        actions.addMenuItem(rafraichir);

        let ouvrir = new PopupMenu.PopupMenuItem("Ouvrir LA (residents, pont)");
        ouvrir.connect("activate", Lang.bind(this, function () {
            try {
                Util.trySpawn([BOUTON]);
            } catch (e) {
                // si l'entree n'est pas la, on le dit par l'etiquette -- jamais par un silence
                this.set_applet_tooltip("l'entree la est introuvable (" + BOUTON + ")");
            }
        }));
        actions.addMenuItem(ouvrir);
        this.menu.addMenuItem(actions);
    },

    on_applet_clicked: function() {
        this._remplirMenu();
        this.menu.toggle();
        this._demanderControle();               // la liste complete arrive des qu'elle est prete
    },

    on_applet_removed_from_panel: function() {
        if (this.boucle) {
            Mainloop.source_remove(this.boucle);
            this.boucle = 0;
        }
        this.enCours = false;
    }
};

function main(metadata, orientation, instance_id) {
    return new LaStatusApplet(metadata, orientation, instance_id);
}
