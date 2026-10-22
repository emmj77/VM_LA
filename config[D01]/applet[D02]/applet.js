// id: G01
// LA_Info -- le panneau de LA. Il ne mesure rien et ne decide rien : il dessine.
//
// UN PRODUCTEUR : board.py --json, servi par le pont sur /board. Le menu (sections, ordre, titres,
// icones, barres) vient de la_config. Ici il n y a donc AUCUN titre, AUCUNE icone, AUCUN ratio
// ecrit en dur : le panneau lit un objet et le pose.
//
// Un objet ressemble a ceci :
//   { "at": "...", "refresh": 5, "faults": 0, "bar": ["residents", "ram of LA"],
//     "sections": [ { "name": "LA", "icon": "🟢", "rows": [
//         {"title": "approbation", "verdict": "3", "ok": true, "kind": "state", "ratio": null,
//          "tone": null, "icon": "✍"} ] } ] }

const Applet = imports.ui.applet;
const PopupMenu = imports.ui.popupMenu;
const Mainloop = imports.mainloop;
const Settings = imports.ui.settings;
const St = imports.gi.St;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const Clutter = imports.gi.Clutter;

const DOT_WIDTH = 18;
const TITLE_WIDTH = 150;
const EMO_WIDTH = 22;
const BAR_WIDTH = 72;
const ICON_DIR = GLib.get_home_dir() + "/.local/share/cinnamon/applets/LA_Info@moussa/icons";
const CACHE = GLib.get_home_dir() + "/.cache/la_info_board.json";

// la pastille : verte, grise (rien a mesurer), rouge (en faute)
const BADGE = { ok: "la-active.svg", note: "la-disabled.svg", ko: "la-disabled.svg" };

function parseBoard(text) {
    const o = JSON.parse(text);
    if (!o || !(o.sections instanceof Array)) { throw new Error("pas de sections"); }
    return o;
}

class LAInfoApplet extends Applet.TextIconApplet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        super(orientation, panelHeight, instanceId);

        this._ready = false;
        this._board = null;
        this._when = null;
        this._timer = 0;
        this._reading = false;
        this.setAllowedLayout(Applet.AllowedLayout.BOTH);

        this._settings = new Settings.AppletSettings(this, metadata.uuid, instanceId);
        this._settings.bind("url", "url", () => { if (this._ready) { this._read(); } });
        this._settings.bind("board", "board", () => { });
        this._settings.bind("seconds", "seconds", () => { if (this._ready) { this._restartWatch(); } });
        ["url", "board"].forEach((k) => {
            if (!this[k]) { try { this[k] = this._settings.getValue(k); } catch (e) { } }
        });

        this._menu = new Applet.AppletPopupMenu(this, orientation);
        this._manage = new PopupMenu.PopupMenuManager(this);
        this._manage.addMenu(this._menu);

        this._board = this._fromCache();
        this._paint();
        this._ready = true;
        this._read();
        this._restartWatch();
        // les octets du tunnel se lisent dans /proc : deux secondes, sans lancer un seul processus
        this._netWatch = Mainloop.timeout_add_seconds(2, () => this._netTick());
    }

    // ---- le cache : le dernier objet connu, pour ne pas ouvrir sur du vide
    _fromCache() {
        try {
            const [, bytes] = GLib.file_get_contents(CACHE);
            return parseBoard(bytes.toString());
        } catch (e) {
            return null;
        }
    }

    _restartWatch() {
        if (this._timer) { Mainloop.source_remove(this._timer); }
        this._timer = Mainloop.timeout_add_seconds(this.seconds || 15, () => {
            this._read();
            return true;
        });
    }

    _rows() {
        const out = [];
        if (!this._board) { return out; }
        (this._board.sections || []).forEach((s) => {
            (s.rows || []).forEach((r) => { r.section = s.name; out.push(r); });
        });
        return out;
    }

    // ---- la lecture : une URL, rien d autre
    _read() {
        if (this._reading || !this.url) { return; }
        this._reading = true;

        let proc;
        try {
            proc = Gio.Subprocess.new(["curl", "-fsS", "-m", "20", this.url],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch (e) {
            this._reading = false;
            global.logError("LA_Info : curl n'a pas pu etre lance : " + e.message);
            this._fail("le pont ne se lance pas");
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

            let text = "";
            try { text = p.communicate_utf8_finish(res)[1] || ""; } catch (e) { text = ""; }

            let obj = null;
            try { obj = parseBoard(text); } catch (e) { obj = null; }

            if (!obj) {
                // le pont dort ou il n a pas repondu : on garde ce qu on avait, et on le dit
                this._stale = true;
                if (!this._board) { this._fail("le pont est muet (" + (this.url || "?") + ")"); }
                else { this._paint(); }
                return;
            }
            this._stale = false;
            this._board = obj;
            try { GLib.file_set_contents(CACHE, text); } catch (e) { }
            this._when = new Date();
            this._approval = this._demande();
            this._paint();
            this._dessinerLeMenu();
            this._updateNet();
        });
    }

    _fail(message) {
        this._board = { at: "", refresh: 0, faults: 1, bar: [], sections: [
            { name: "LA", icon: "\u26A0", rows: [
                { title: "board", verdict: message, ok: false, kind: "state", ratio: null,
                  tone: null, icon: "\u26A0" } ] } ] };
        this._paint();
    }

    // L APPROBATION SE LIT DANS LES LIGNES : la ligne « approbation » porte le geste en clair.
    // LE GESTE VIENT ECRIT : la porte le pose dans la demande, le board le transporte.
    // L applet ne decoupe plus « asked 812s ago » pour en deviner le nom.
    _demande() {
        let found = null;
        this._rows().forEach((l) => {
            if (l.title !== "approbation" || found) { return; }
            const geste = String(l.gesture || "").trim();
            if (!geste) { return; }
            const mots = geste.split(/\s+/);
            found = [mots[0], mots.slice(1).join(" ")];
        });
        return found;
    }

    // ---- ce qui se voit sans rien ouvrir : les lignes que la config met dans la barre
    _paint() {
        const rows = this._rows();
        if (!rows.length) {
            this.set_applet_icon_path(ICON_DIR + "/la-unknown.svg");
            this.set_applet_label("?");
            this.set_applet_tooltip("le board n'a rien rendu");
            return;
        }
        this.set_applet_icon_path(ICON_DIR + "/" + BADGE.ok);
        const wanted = (this._board && this._board.bar) || [];
        const courts = [];
        rows.forEach((l) => {
            if (wanted.indexOf(l.title) > -1) { courts.push((l.icon || "\u2022") + " " + l.verdict); }
        });
        this.set_applet_label(courts.join("  "));
        const hour = this._when ? this._when.toLocaleTimeString() : "";
        this.set_applet_tooltip(rows.map((l) => l.title + " : " + l.verdict).join("\n")
            + (hour ? "\n\nrelu a " + hour : ""));
    }

    // ---- TAILSCALE : un etat et des octets, en direct. Le board ne le mesure pas, il vit ici.
    _fmt(b) {
        if (b >= 1073741824) { return (b / 1073741824).toFixed(1) + " GB"; }
        if (b >= 1048576) { return (b / 1048576).toFixed(1) + " MB"; }
        if (b >= 1024) { return (b / 1024).toFixed(1) + " kB"; }
        return b + " B";
    }

    _netBytes() {
        try {
            const [, data] = GLib.file_get_contents("/proc/net/dev");
            const lines = data.toString().split("\n");
            for (let k = 0; k < lines.length; k++) {
                if (lines[k].indexOf("tailscale0:") === -1) { continue; }
                const f = lines[k].split(":")[1].trim().split(/\s+/);
                return { rx: parseInt(f[0], 10) || 0, tx: parseInt(f[8], 10) || 0 };
            }
        } catch (e) { }
        return null;
    }

    _netRow() {
        const now = Date.now() / 1000;
        const b = this._netBytes();
        let rate = "";
        if (b && this._netPrev) {
            const dt = now - this._netPrev.t;
            if (dt > 0.5) {
                const d = (b.rx - this._netPrev.rx) + (b.tx - this._netPrev.tx);
                if (d > 0) { rate = " \u00b7 " + this._fmt(Math.round(d / dt)) + "/s"; }
            }
        }
        if (b) { this._netPrev = { t: now, rx: b.rx, tx: b.tx }; }
        const up = this._netUp === true;
        const state = up ? "up" : (this._netState || "down");
        return { title: "tailscale", verdict: state + rate, ok: up, kind: "state", ratio: null,
                 tone: null, icon: "\u{1F310}", section: "RESEAU" };
    }

    _putNet(row) {
        if (!this._board) { return false; }
        const secs = this._board.sections || [];
        for (let i = 0; i < secs.length; i++) {
            if (secs[i].name !== row.section) { continue; }
            const rows = secs[i].rows || [];
            for (let j = 0; j < rows.length; j++) {
                if (rows[j].title === "tailscale") { rows[j] = row; return true; }
            }
            rows.push(row);
            return true;
        }
        return false;
    }

    _netTick() {
        let row;
        try { row = this._netRow(); } catch (e) {
            global.logError("LA_Info net: " + e.message);
            return true;
        }
        if (this._putNet(row)) { this._paint(); }
        if (this._netLabel) { this._netLabel.text = row.verdict; }
        return true;
    }

    _updateNet() {
        let proc;
        try {
            proc = Gio.Subprocess.new(["tailscale", "status", "--json"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch (e) { return; }
        proc.communicate_utf8_async(null, null, (p, res) => {
            let d = {};
            try { d = JSON.parse(p.communicate_utf8_finish(res)[1] || "{}"); } catch (e) { return; }
            this._netUp = (d.BackendState || "") === "Running";
            this._netState = d.BackendState || "down";
            this._netTick();
        });
    }

    // ---- LE MENU : les sections du producteur, telles quelles
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
        children.push(this._smallLabel(line.icon || "\u2022", "la-info-emoji", EMO_WIDTH));
        children.push(this._smallLabel(String(line.title).toUpperCase(), "la-info-title", TITLE_WIDTH));
        children.push(this._pastille(line));
        children.push(line.kind === "ratio" && line.ratio !== null
            ? this._barre(line) : this._slotVide());
        const verdict = this._smallLabel(line.verdict, "la-info-verdict", 0, Clutter.ActorAlign.END);
        children.push(verdict);
        if (line.title === "tailscale") { this._netLabel = verdict; }
        return this._rangee(children);
    }

    // Une health doit valoir 1 et sanctionne ; une share chauffe (vert, ambre, rouge).
    _couleurDe(line) {
        if (line.tone !== "share") { return line.ratio >= 1 ? "la-info-full" : "la-info-partial"; }
        if (line.ratio >= 0.8) { return "la-info-hot"; }
        if (line.ratio >= 0.5) { return "la-info-partial"; }
        return "la-info-full";
    }

    _slotVide() {
        const box = new St.BoxLayout({ style_class: "la-info-slot" });
        box.set_width(BAR_WIDTH);
        box.add_child(new St.Widget({ x_expand: true }));
        return box;
    }

    _pastille(line) {
        const box = new St.BoxLayout({ style_class: "la-info-slot" });
        box.set_width(DOT_WIDTH);
        box.add_child(new St.Widget({ x_expand: true }));
        const dot = new St.Icon({
            gicon: Gio.icon_new_for_string(ICON_DIR + "/" + (line.ok ? BADGE.ok : BADGE.ko)),
            icon_size: 12,
            y_align: Clutter.ActorAlign.CENTER,
        });
        box.add_child(dot);
        box.add_child(new St.Widget({ x_expand: true }));
        return box;
    }

    _barre(line) {
        const rail = new St.BoxLayout({ style_class: "la-info-rail" });
        rail.set_width(BAR_WIDTH);
        const filled = Math.round(BAR_WIDTH * Math.min(1, Math.max(0, line.ratio)));
        if (filled > 0) {
            rail.add_child(new St.Widget({ style_class: this._couleurDe(line), width: filled }));
        }
        rail.add_child(new St.Widget({ x_expand: true }));
        return rail;
    }

    _dessinerLeMenu() {
        this._menu.removeAll();
        if (this._mesRangees) {
            this._mesRangees.forEach((r) => { try { r.destroy(); } catch (e) { } });
        }
        this._mesRangees = [];

        const when = this._when ? this._when.toLocaleTimeString() : "jamais";
        const head = this._rangee([this._smallLabel("LA_Info", "la-info-head")]);
        const hour = this._rangee([this._smallLabel("mesures relues a " + when
            + (this._stale ? " \u00b7 le pont ne repond pas, ceci est le dernier objet" : ""),
            "la-info-when")]);
        [head, hour].forEach((r) => { this._menu.box.add_child(r); this._mesRangees.push(r); });

        this._netLabel = null;
        const secs = (this._board && this._board.sections) || [];
        secs.forEach((sec) => {
            if (!sec.rows || !sec.rows.length) { return; }
            const t = this._rangee([this._smallLabel((sec.icon ? sec.icon + "  " : "") + sec.name,
                                                    "la-info-section")]);
            this._menu.box.add_child(t);
            this._mesRangees.push(t);
            sec.rows.forEach((r) => {
                const l = this._ligneDeMenu(r);
                this._menu.box.add_child(l);
                this._mesRangees.push(l);
            });
        });

        if (this._approval) {
            const [outil, geste] = this._approval;
            const approve = new PopupMenu.PopupMenuItem(
                "\u2713  Approuver " + outil + " " + geste + " (une fois)");
            approve.connect("activate", () => { this._approve(outil, geste); });
            this._menu.addMenuItem(approve);
        }

        const rafraichir = new PopupMenu.PopupMenuItem("\u21bb  Relire le board, maintenant");
        rafraichir.connect("activate", () => { this._read(); });
        this._menu.addMenuItem(rafraichir);
    }

    _approve(outil, geste) {
        try {
            const proc = Gio.Subprocess.new(["dash", this.board, "engine", "engine.approve", "op=allow"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE | Gio.SubprocessFlags.STDIN_PIPE);
            proc.communicate_utf8_async(outil + " " + geste, null, (p, res) => {
                try {
                    const [, sortie, erreur] = p.communicate_utf8_finish(res);
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
