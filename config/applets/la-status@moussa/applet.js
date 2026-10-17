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

const UUID = "la-status@moussa";
const TABLEAU = GLib.get_home_dir() + "/Documents/VM_LA/config/engine/board.sh";
const BOUTON = GLib.get_home_dir() + "/.local/bin/la";
const SECONDES = 30;      // une demande coute ~1 s : on ne la fait pas toutes les secondes
const LARGEUR = "72";     // la largeur des lignes du menu, en colonnes

function LaStatusApplet(metadata, orientation, instance_id) {
    this._init(metadata, orientation, instance_id);
}

LaStatusApplet.prototype = {
    __proto__: Applet.TextApplet.prototype,

    _init: function(metadata, orientation, instance_id) {
        Applet.TextApplet.prototype._init.call(this, orientation, instance_id);
        this.setAllowedLayout(Applet.AllowedLayout.BOTH);

        // LE MENU : construit par nous, montre par Cinnamon.
        this.menuManager = new PopupMenu.PopupMenuManager(this);
        this.menu = new Applet.AppletPopupMenu(this, orientation);
        this.menuManager.addMenu(this.menu);

        this.enCours = false;
        this.controle = [];                     // les lignes de la liste, telles que le tableau les rend
        this.ligne = "LA ...";
        this.set_applet_label(this.ligne);
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
            this._rendreLigne("LA ? le tableau est introuvable");
            return;
        }
        this.enCours = true;
        try {
            Util.spawn_async([TABLEAU, "--line", "--largeur", LARGEUR],
                             Lang.bind(this, this._rendreLigne));
        } catch (e) {
            this.enCours = false;
            this._rendreLigne("LA ? la demande n'est pas partie");
        }
    },

    _demanderControle: function() {
        try {
            Util.spawn_async([TABLEAU, "--check", "--largeur", LARGEUR],
                             Lang.bind(this, this._rendreControle));
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
        for (let i = 0; i < this.controle.length; i++) {
            let ligne = new PopupMenu.PopupMenuItem(this.controle[i]);
            // LA LISTE EST UNE TABLE A CHASSE FIXE : ses points de conduite sont calcules sur des
            // colonnes, pour une police monospace. Dans la police proportionnelle du menu, ces
            // points partent en brouillard et RIEN ne s'aligne -- c'etait le vrai defaut. On donne
            // donc a ces lignes-la (et a elles seules) la police qui va avec leur forme.
            ligne.label.add_style_class_name("la-mono");
            section.addMenuItem(ligne);
        }
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
