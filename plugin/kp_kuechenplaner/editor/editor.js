'use strict';
/* Küchenplaner-Editor: Formulare werden aus den JSON-Schemata erzeugt (schemas/), Listen sind in der Anzahl veränderbar.
   Ruby-Seite: lib/kp/editor/sitzung.rb (Prüfen, Speichern, Neuzeichnen). Hier keine Abhängigkeiten. */

const S = {
  schemas: {}, katalog: { dateien: [], vorlagen: [], ordner: [] },
  projekt: null, dokumente: {}, datei: null, tab: 'projekt', auswahl: { typ: 'projekt' },
  live: false, warnungen: [], vorlagenCache: {}, timer: null, laeuft: false, nochmal: null, offen: new WeakSet(), neuFormular: null
};
const ARTEN = [
  ['vorlage', 'Vorlagen'], ['beschlag', 'Beschläge'], ['beschlagset', 'Beschlag-Sets'], ['regeldatei', 'Regeln']
];
const REF = {
  instanz: 'zeile.schema.json#/$defs/instanz', frontfeld: 'vorlage.schema.json#/$defs/frontfeld', einbau: 'vorlage.schema.json#/$defs/einbau'
};
// Listen der Vorlage, deren Anzahl im Projekt pro Schrank geändert werden kann (als Override gespeichert)
const ANPASSBAR = [
  { pfad: 'front.felder', titel: 'Frontfelder (von unten nach oben)', ref: REF.frontfeld },
  { pfad: 'einbauten', titel: 'Einbauten', ref: REF.einbau }
];

/* ---------- Hilfen ---------- */
const $ = (sel, wurzel = document) => wurzel.querySelector(sel);
function h(tag, attrs = {}, ...kinder) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'text') e.textContent = v;
    else if (k === 'class') e.className = v;
    else if (k === 'value') e.value = v;
    else if (k === 'checked') e.checked = !!v;
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const k of kinder.flat()) if (k !== null && k !== undefined && k !== false) e.append(k.nodeType ? k : document.createTextNode(String(k)));
  return e;
}
const klon = x => (x === undefined ? undefined : JSON.parse(JSON.stringify(x)));
const pfadText = p => p.join('.');

/* ---------- Brücke zu Ruby ---------- */
let rpcZaehler = 0;
const rpcWarten = {};
function rpc(aktion, daten) {
  return new Promise(ok => {
    const id = ++rpcZaehler;
    rpcWarten[id] = ok;
    window.sketchup.kp(JSON.stringify({ id, aktion, daten: daten || {} }));
  });
}
window.kpAntwort = (id, json) => {
  const ok = rpcWarten[id];
  delete rpcWarten[id];
  if (ok) ok(typeof json === 'string' ? JSON.parse(json) : json);
};

/* ---------- Schema ---------- */
function aufloesen(sch, datei) {
  let n = 0;
  while (sch && sch.$ref && n++ < 20) {
    const [rd, anker] = sch.$ref.split('#');
    datei = rd || datei;
    let k = S.schemas[datei];
    (anker || '').split('/').filter(Boolean).forEach(p => { k = k[p]; });
    const extra = {};
    if (sch.description) extra.description = sch.description;
    if (sch.default !== undefined) extra.default = sch.default;
    sch = { ...k, ...extra };
  }
  return [sch || {}, datei];
}
const typen = sch => [].concat(sch.type || []);
const istListe = sch => typen(sch).includes('array') || !!sch.items;
const istObjekt = sch => typen(sch).includes('object') || !!sch.properties || (!sch.type && !!sch.additionalProperties);
const istMass = sch => !!sch.oneOf && sch.oneOf.some(o => o.type === 'number');

function wennPasst(bed, wert) {
  return Object.entries(bed.properties || {}).every(([k, s]) => {
    if (!wert) return false;
    if ('const' in s) return wert[k] === s.const;
    if (s.enum) return s.enum.includes(wert[k]);
    return true;
  });
}
// Eigenschaften inkl. allOf/if/then (z. B. Regeln: je nach "art" andere Felder)
function effektiv(sch, datei, wert) {
  [sch, datei] = aufloesen(sch, datei);
  if (!sch.allOf) return [sch, datei];
  const props = { ...(sch.properties || {}) };
  const pflicht = [...(sch.required || [])];
  for (const a of sch.allOf) {
    let gilt = true, ziel = a;
    if (a.if) { gilt = wennPasst(a.if, wert); ziel = a.then || {}; }
    if (!gilt) continue;
    const [z] = aufloesen(ziel, datei);
    Object.assign(props, z.properties || {});
    pflicht.push(...(z.required || []));
  }
  return [{ ...sch, properties: props, required: [...new Set(pflicht)] }, datei];
}
function standardWert(sch, datei) {
  [sch, datei] = aufloesen(sch, datei);
  if (sch.default !== undefined) return klon(sch.default);
  if (sch.enum) return sch.enum[0];
  if (istListe(sch)) {
    return Array.from({ length: sch.minItems || 0 }, () => (sch.items ? standardWert(sch.items, datei) : 0));
  }
  if (istObjekt(sch)) {
    const o = {};
    for (const k of sch.required || []) o[k] = (sch.properties || {})[k] ? standardWert(sch.properties[k], datei) : '';
    return o;
  }
  const t = typen(sch);
  if (t.includes('number') || t.includes('integer') || istMass(sch)) return 0;
  if (t.includes('boolean')) return false;
  return '';
}
function schemaVon(ref) {
  const [sch, datei] = aufloesen({ $ref: ref }, '');
  return [sch, datei];
}

/* ---------- Änderungen, Speichern, Prüfen ---------- */
function halter() { return S.tab === 'projekt' ? S.projekt : S.datei; }

function geaendert(struktur) {
  const hd = halter();
  if (!hd) return;
  const jetzt = Date.now();
  if (struktur || jetzt - hd.zeit > 600) {
    hd.undo.push(hd.stand);
    if (hd.undo.length > 60) hd.undo.shift();
  }
  hd.zeit = jetzt;
  hd.stand = JSON.stringify(hd.doc);
  hd.dirty = true;
  status('Ungespeicherte Änderungen');
  plane(hd);
  markiereBaum();
}
function plane(hd) {
  clearTimeout(S.timer);
  S.timer = setTimeout(() => (S.live ? speichere(hd, true) : pruefe(hd)), 400);
}
function neuerHalter(pfad, art, doc, neu) {
  const hd = { pfad, art, doc, neu: !!neu, dirty: !!neu, undo: [], stand: JSON.stringify(doc), zeit: 0, fehler: [] };
  S.dokumente[pfad] = hd;
  return hd;
}
async function pruefe(hd) {
  const r = await rpc('pruefen', { art: hd.art, doc: hd.doc });
  hd.fehler = r.fehler || [];
  anzeigeFehler(hd);
}
async function speichere(hd, zeichnen) {
  clearTimeout(S.timer);
  if (S.laeuft) { S.nochmal = [hd, zeichnen]; return; }
  S.laeuft = true;
  try {
    const nutzlast = { art: hd.art, pfad: hd.pfad, doc: hd.doc, zeichnen };
    if (hd !== S.projekt && S.projekt) nutzlast.projekt = S.projekt.doc;
    const r = await rpc('speichern', nutzlast);
    if (r.fehler_text) { status(r.fehler_text, 'fehler'); return; }
    hd.fehler = r.fehler || [];
    if (r.gespeichert) {
      hd.dirty = false;
      hd.neu = false;
      S.warnungen = r.warnungen || [];
      if (r.katalog) { S.katalog = r.katalog; S.vorlagenCache = {}; }
      const teile = ['Gespeichert'];
      if (r.gezeichnet) teile.push('Küche aktualisiert');
      else if (zeichnen && r.hinweis) teile.push(r.hinweis);
      status(teile.join(' · '), S.warnungen.length ? 'warn' : 'ok');
      if (r.katalog) renderSeitenleiste();
    } else {
      status(`${hd.fehler.length} Fehler – nicht gespeichert`, 'fehler');
    }
    anzeigeFehler(hd);
    markiereBaum();
  } finally {
    S.laeuft = false;
    if (S.nochmal) { const [a, b] = S.nochmal; S.nochmal = null; speichere(a, b); }
  }
}
function status(text, art) {
  const s = $('#status');
  s.textContent = text;
  s.className = art || '';
}
function anzeigeFehler(hd) {
  markiereFelder(hd);
  const f = $('#fehlerliste');
  f.replaceChildren();
  const zeilen = [
    ...hd.fehler.map(x => [x.pfad, `${x.pfad || '(Datei)'}: ${x.meldung}`, '']),
    ...S.warnungen.map(w => ['', w, 'warn'])
  ];
  zeilen.forEach(([pfad, text, art]) => f.append(h('div', { class: art, text, onclick: () => zeigePfad(pfad) })));
  f.hidden = zeilen.length === 0;
  if (hd.fehler.length) status(`${hd.fehler.length} Fehler`, 'fehler');
  else if ($('#status').className === 'fehler') status('', '');
}
function findePfad(pfad) {
  const teile = pfad ? pfad.split('.') : [];
  for (;;) {
    const el = $(`[data-pfad="${CSS.escape(teile.join('.'))}"]`);
    if (el || !teile.length) return el;
    teile.pop();
  }
}
function markiereFelder(hd) {
  document.querySelectorAll('.fehler-feld').forEach(e => { e.classList.remove('fehler-feld'); e.removeAttribute('title'); });
  for (const f of hd.fehler) {
    const el = findePfad(f.pfad);
    if (el) { el.classList.add('fehler-feld'); el.title = f.meldung; }
  }
}
function zeigePfad(pfad) {
  const el = findePfad(pfad);
  if (el) { const d = el.closest('details'); if (d) d.open = true; el.scrollIntoView({ block: 'center' }); }
}

/* ---------- Eingabefelder ---------- */
function geaendertHook(opts) { return opts.geaendert || geaendert; }

function zeile(label, sch, pflicht, widget, block) {
  return h('div', { class: 'feld' + (block ? ' block' : '') },
    h('label', {}, label, pflicht ? h('span', { class: 'pflicht', text: ' *' }) : null,
      sch.description ? h('small', { text: sch.description }) : null),
    widget);
}

function jsonFeld(wert, setWert, pfad, opts) {
  const ta = h('textarea', { 'data-pfad': pfadText(pfad), spellcheck: 'false' });
  ta.value = wert === undefined ? '' : JSON.stringify(wert);
  ta.addEventListener('input', () => {
    if (ta.value.trim() === '') { setWert(undefined); ta.classList.remove('fehler-feld'); geaendertHook(opts)(); return; }
    try { setWert(JSON.parse(ta.value)); ta.classList.remove('fehler-feld'); geaendertHook(opts)(); } catch (e) { ta.classList.add('fehler-feld'); }
  });
  return ta;
}

function skalar(sch, datei, wert, setWert, pfad, opts, pflicht) {
  const gh = () => geaendertHook(opts)();
  const t = typen(sch);
  const p = pfadText(pfad);
  if (sch.enum) {
    const sel = h('select', { 'data-pfad': p });
    if (!pflicht) sel.append(h('option', { value: '', text: '' }));
    sch.enum.forEach(v => sel.append(h('option', { value: String(v), text: String(v) })));
    if (wert !== undefined && !sch.enum.includes(wert)) sel.append(h('option', { value: String(wert), text: String(wert) }));
    sel.value = wert === undefined ? '' : String(wert);
    sel.addEventListener('change', () => { setWert(sel.value === '' ? undefined : sel.value); gh(); });
    return sel;
  }
  if ('const' in sch) return h('input', { type: 'text', value: String(sch.const), disabled: true, 'data-pfad': p });
  if (t.includes('boolean')) {
    const cb = h('input', { type: 'checkbox', checked: !!wert, 'data-pfad': p });
    cb.addEventListener('change', () => { setWert(cb.checked); gh(); });
    return cb;
  }
  if (t.includes('number') || t.includes('integer')) {
    const inp = h('input', { type: 'number', step: t.includes('integer') ? '1' : 'any', 'data-pfad': p });
    inp.value = wert === undefined ? '' : wert;
    inp.addEventListener('input', () => {
      if (inp.value === '') setWert(pflicht ? 0 : undefined); else setWert(Number(inp.value));
      gh();
    });
    return inp;
  }
  if (istMass(sch)) { // Zahl oder Formel ("=B-2*S")
    const inp = h('input', { type: 'text', 'data-pfad': p });
    inp.value = wert === undefined ? '' : String(wert);
    inp.addEventListener('input', () => {
      const v = inp.value.trim();
      if (v === '') setWert(pflicht ? 0 : undefined); else setWert(/^-?\d+(\.\d+)?$/.test(v) ? Number(v) : inp.value);
      gh();
    });
    return inp;
  }
  if (t.includes('string')) {
    const inp = h('input', { type: 'text', 'data-pfad': p });
    const liste = opts.vorschlaege && opts.vorschlaege[pfad[pfad.length - 1]];
    if (liste) { // Vorschläge (z. B. vorhandene Materialschlüssel) als Auswahlliste, freie Eingabe bleibt möglich
      const id = 'dl_' + p.replace(/\W/g, '_');
      inp.setAttribute('list', id);
      inp.value = wert === undefined || wert === null ? '' : wert;
      inp.addEventListener('input', () => { setWert(inp.value === '' && !pflicht ? undefined : inp.value); gh(); });
      return h('div', {}, inp, h('datalist', { id }, liste.map(v => h('option', { value: v }))));
    }
    inp.value = wert === undefined || wert === null ? '' : wert;
    inp.addEventListener('input', () => {
      if (inp.value === '') setWert(pflicht ? '' : (t.includes('null') ? null : undefined)); else setWert(inp.value);
      gh();
    });
    return inp;
  }
  return jsonFeld(wert, setWert, pfad, opts);
}

// Beliebiger Wert gemäß Schema; gibt das Eingabe-Element zurück (Objekte/Listen ändern 'wert' direkt)
function feld(sch, datei, wert, setWert, pfad, opts, pflicht) {
  [sch, datei] = aufloesen(sch, datei);
  if (istListe(sch)) return listenEditor(sch, datei, wert, pfad, opts);
  if (istObjekt(sch) && !sch.enum) return objektEditor(sch, datei, wert, pfad, opts);
  if (sch.oneOf && !istMass(sch)) return jsonFeld(wert, setWert, pfad, opts);
  return skalar(sch, datei, wert, setWert, pfad, opts, pflicht);
}

function objektEditor(sch, datei, wert, pfad, opts = {}) {
  const box = h('div', { 'data-pfad': pfadText(pfad) });
  const gh = () => geaendertHook(opts)();
  function baue() {
    box.replaceChildren();
    const [es, ed] = effektiv(sch, datei, wert);
    const props = es.properties || {};
    const pflicht = new Set(es.required || []);
    const ausser = new Set(opts.ausser || []);
    for (const k of Object.keys(props)) {
      if (ausser.has(k)) continue;
      const [ps, pd] = aufloesen(props[k], ed);
      const p = [...pfad, k];
      const setze = v => { if (v === undefined) delete wert[k]; else wert[k] = v; };
      if (opts.ersetze && opts.ersetze[k]) { box.append(opts.ersetze[k](k, wert, p)); continue; }
      const komplex = (istListe(ps) || (istObjekt(ps) && !ps.enum)) && !(ps.oneOf);
      if (komplex && wert[k] === undefined) {
        box.append(zeile(k, ps, pflicht.has(k), h('button', {
          text: '+ hinzufügen', onclick: () => { wert[k] = standardWert(ps, pd); gh(); baue(); }
        })));
      } else if (komplex) {
        const fs = h('fieldset', {}, h('legend', { text: k }),
          ps.description ? h('div', { class: 'hinweis', text: ps.description }) : null,
          feld(ps, pd, wert[k], setze, p, opts, pflicht.has(k)));
        if (!pflicht.has(k)) {
          fs.querySelector('legend').append(' ', h('button', { class: 'klein', title: 'Entfernen', text: '✕', onclick: () => { delete wert[k]; gh(); baue(); } }));
        }
        box.append(fs);
      } else {
        box.append(zeile(k, ps, pflicht.has(k), feld(ps, pd, wert[k], setze, p, opts, pflicht.has(k))));
      }
    }
    // Felder ohne Schema-Eintrag oder freie Schlüssel (z. B. Materialien, Zuordnungen)
    const frei = es.additionalProperties !== false && (Object.keys(props).length === 0 || es.additionalProperties);
    const fremd = Object.keys(wert).filter(k => !(k in props) && !ausser.has(k) && !(opts.verberge || []).includes(k));
    if (frei || fremd.length) box.append(dictEditor(es, ed, wert, pfad, opts, Object.keys(props), baue));
  }
  baue();
  return box;
}

function dictEditor(sch, datei, wert, pfad, opts, bekannt, neuAufbau) {
  const box = h('div', { class: 'dict' });
  const gh = () => geaendertHook(opts)();
  const verberge = new Set([...(opts.verberge || []), ...(opts.ausser || []), ...bekannt]);
  const wsch = sch.additionalProperties && typeof sch.additionalProperties === 'object' ? sch.additionalProperties : null;
  const [ns] = sch.propertyNames ? aufloesen(sch.propertyNames, datei) : [{}];
  Object.keys(wert).filter(k => !verberge.has(k)).forEach(k => {
    const p = [...pfad, k];
    const schluessel = ns.enum
      ? h('select', {}, [k, ...ns.enum.filter(e => e !== k && !(e in wert))].map(e => h('option', { value: e, text: e })))
      : h('input', { type: 'text', value: k });
    schluessel.value = k;
    schluessel.addEventListener('change', () => {
      const neu = schluessel.value.trim();
      if (!neu || neu === k || neu in wert) { schluessel.value = k; return; }
      const alt = Object.entries(wert);
      alt.forEach(([kk]) => delete wert[kk]);
      alt.forEach(([kk, v]) => { wert[kk === k ? neu : kk] = v; });
      gh(); neuAufbau();
    });
    const setze = v => { if (v === undefined) delete wert[k]; else wert[k] = v; };
    const w = wsch ? feld(wsch, datei, wert[k], setze, p, opts, true) : jsonFeld(wert[k], setze, p, opts);
    const komplex = wsch && (istObjekt(aufloesen(wsch, datei)[0]) || istListe(aufloesen(wsch, datei)[0]));
    box.append(h('div', { class: 'feld' + (komplex ? ' block' : '') },
      h('div', {}, schluessel, h('button', { class: 'klein', title: 'Eintrag entfernen', text: '✕', onclick: () => { delete wert[k]; gh(true); neuAufbau(); } })),
      w));
  });
  const neuName = h('input', { type: 'text', placeholder: ns.enum ? '' : 'Neuer Schlüssel' });
  const add = () => {
    const name = ns.enum ? (ns.enum.find(e => !(e in wert)) || '') : neuName.value.trim();
    if (!name || name in wert) return;
    wert[name] = wsch ? standardWert(wsch, datei) : '';
    gh(true); neuAufbau();
  };
  box.append(h('div', { class: 'feld' }, ns.enum ? h('span') : neuName, h('button', { text: '+ Eintrag', onclick: add })));
  return box;
}

function titelVon(item) {
  if (item === null || typeof item !== 'object') return String(item);
  const k = ['pos', 'id', 'code', 'art', 'rolle', 'name', 'vorlage'].filter(x => item[x] !== undefined && typeof item[x] !== 'object');
  const zusatz = ['anteil', 'hoehe', 'anzahl', 'breite'].filter(x => item[x] !== undefined).map(x => `${x}: ${item[x]}`);
  return [k.slice(0, 2).map(x => item[x]).join(' · '), zusatz.join(', ')];
}

function listenEditor(sch, datei, wert, pfad, opts = {}) {
  const box = h('div', { 'data-pfad': pfadText(pfad) });
  const gh = s => geaendertHook(opts)(s);
  const [is, idat] = aufloesen(sch.items || {}, datei);
  const einfach = !istObjekt(is) && !istListe(is);
  const fest = sch.minItems !== undefined && sch.minItems === sch.maxItems;
  if (fest && einfach) { // z. B. Position [x, y, z]
    const v = h('div', { class: 'vec', 'data-pfad': pfadText(pfad) });
    wert.forEach((x, i) => v.append(feld(is, idat, x, nv => { wert[i] = nv; }, [...pfad, String(i)], opts, true)));
    return v;
  }
  function baue() {
    box.replaceChildren();
    wert.forEach((item, i) => {
      const p = [...pfad, String(i)];
      const bewege = d => { const j = i + d; if (j < 0 || j >= wert.length) return; [wert[i], wert[j]] = [wert[j], wert[i]]; gh(true); baue(); };
      const knoepfe = [
        h('button', { class: 'klein', title: 'Nach oben/vorn', text: '↑', disabled: i === 0, onclick: e => { e.preventDefault(); bewege(-1); } }),
        h('button', { class: 'klein', title: 'Nach unten/hinten', text: '↓', disabled: i === wert.length - 1, onclick: e => { e.preventDefault(); bewege(1); } }),
        h('button', { class: 'klein', title: 'Duplizieren', text: '⧉', onclick: e => { e.preventDefault(); wert.splice(i + 1, 0, klon(item)); gh(true); baue(); } }),
        h('button', { class: 'klein', title: 'Entfernen', text: '✕', onclick: e => { e.preventDefault(); wert.splice(i, 1); gh(true); baue(); } })
      ];
      if (einfach) {
        box.append(h('div', { class: 'feld' }, feld(is, idat, item, v => { wert[i] = v; }, p, opts, true), h('div', {}, knoepfe)));
        return;
      }
      const [t1, t2] = [].concat(titelVon(item));
      const d = h('details', { class: 'zeile-liste' },
        h('summary', {}, h('span', { text: `${i + 1}.` }), h('span', { class: 'titel', text: t1 || 'Eintrag' }), h('span', { class: 'wert', text: t2 || '' }), knoepfe),
        h('div', { class: 'koerper' }, feld(is, idat, item, v => { wert[i] = v; }, p, opts, true)));
      d.open = S.offen.has(item) || (!S.offen.has(item) && wert.length <= 5);
      S.offen.add(item);
      d.addEventListener('toggle', () => { if (d.open) S.offen.add(item); });
      box.append(d);
    });
    if (!fest) {
      box.append(h('div', {}, h('button', {
        text: '+ Eintrag', onclick: () => { wert.push(standardWert(is, idat)); gh(true); baue(); }
      }), opts.listenKnoepfe ? opts.listenKnoepfe(wert, () => { gh(true); baue(); }) : null));
    }
  }
  baue();
  return box;
}

/* ---------- Projekt: Baum und Details ---------- */
function elementTitel(e) { return `${e.pos || '?'} ${e.vorlage || ''}${e.breite ? ' · ' + e.breite : ''}`; }

function knoten(text, aktiv, klick, ebene, pfadPrefix) {
  const k = h('div', { class: `knoten eben${ebene}` + (aktiv ? ' aktiv' : ''), onclick: klick }, h('span', { text }));
  if (pfadPrefix !== undefined) k.dataset.knoten = pfadPrefix;
  return k;
}
function sel(typ, z, e) { S.auswahl = { typ, z, e }; renderSeitenleiste(); renderDetail(); }
const gleich = (a, typ, z, e) => a.typ === typ && a.z === z && a.e === e;

function projektSeite(wurzel) {
  const hd = S.projekt;
  if (!hd) return;
  const doc = hd.doc;
  const a = S.auswahl;
  wurzel.append(
    knoten('Projekt', a.typ === 'projekt', () => sel('projekt'), 0, ''),
    knoten('Standards', a.typ === 'standards', () => sel('standards'), 0, 'standards'),
    h('div', { class: 'gruppe' }, h('span', { text: 'Zeilen' }), h('button', {
      class: 'klein', text: '+ Zeile', onclick: () => {
        doc.zeilen = doc.zeilen || [];
        const n = doc.zeilen.length + 1;
        doc.zeilen.push({ id: `zeile_${n}`, name: `Zeile ${n}`, ebene: 'unten', start: [0, 0, 0], elemente: [] });
        S.auswahl = { typ: 'zeile', z: doc.zeilen.length - 1 };
        geaendert(true); renderSeitenleiste(); renderDetail();
      }
    })));
  (doc.zeilen || []).forEach((z, zi) => {
    wurzel.append(knoten(z.name || z.id, gleich(a, 'zeile', zi), () => sel('zeile', zi), 1, `zeilen.${zi}`));
    (z.elemente || []).forEach((e, ei) => wurzel.append(knoten(elementTitel(e), gleich(a, 'element', zi, ei), () => sel('element', zi, ei), 2, `zeilen.${zi}.elemente.${ei}`)));
  });
}

function markiereBaum() {
  const hd = halter();
  document.querySelectorAll('[data-knoten]').forEach(k => {
    const pre = k.dataset.knoten;
    const fehler = hd && hd.fehler.some(f => pre === '' ? !f.pfad.startsWith('zeilen') && !f.pfad.startsWith('standards') : (f.pfad === pre || f.pfad.startsWith(pre + '.')));
    k.classList.toggle('fehlerhaft', !!fehler);
  });
  document.querySelectorAll('[data-datei]').forEach(k => {
    const d = S.dokumente[k.dataset.datei];
    k.classList.toggle('ungespeichert', !!(d && d.dirty));
    k.classList.toggle('fehlerhaft', !!(d && d.fehler.length));
  });
}

function vorlagenCodes() { return S.katalog.vorlagen.filter(v => !v.abstrakt).map(v => v.code); }

async function vorlageHolen(code) {
  if (!code) return null;
  if (!(code in S.vorlagenCache)) {
    const r = await rpc('vorlage', { code, projekt: S.projekt ? S.projekt.doc : undefined });
    S.vorlagenCache[code] = r.vorlage || null;
  }
  return S.vorlagenCache[code];
}

function kopfMitAktionen(titel, aktionen) {
  return h('div', { class: 'kopf' }, h('h2', { text: titel }), aktionen);
}

function projektDetail() {
  const hd = S.projekt;
  const d = $('#detail');
  d.replaceChildren();
  if (!hd) {
    d.append(h('div', { class: 'leer' }, h('p', { text: 'Kein Projekt gewählt.' }),
      h('button', { class: 'primaer', text: 'Projekt wählen…', onclick: projektWaehlen })));
    return;
  }
  const doc = hd.doc;
  const a = S.auswahl;
  const opts = { vorschlaege: { material: Object.keys((doc.standards || {}).materialien || {}), kante: Object.keys((doc.standards || {}).kanten || {}) } };
  const [pschema] = [S.schemas['projekt.schema.json']];
  if (a.typ === 'projekt') {
    d.append(kopfMitAktionen('Projekt', h('span', { class: 'hinweis', text: hd.pfad })),
      objektEditor(pschema, 'projekt.schema.json', doc, [], { ...opts, ausser: ['standards', 'zeilen'] }));
  } else if (a.typ === 'standards') {
    const [ss, sd] = aufloesen(pschema.properties.standards, 'projekt.schema.json');
    d.append(kopfMitAktionen('Standards', null), objektEditor(ss, sd, doc.standards, ['standards'], opts));
  } else if (a.typ === 'zeile') {
    const zeileDoc = doc.zeilen[a.z];
    if (!zeileDoc) return;
    d.append(kopfMitAktionen(`Zeile ${zeileDoc.name || zeileDoc.id}`, [
      h('button', { text: '+ Element', onclick: () => {
        const nr = (zeileDoc.elemente || []).length + 1;
        zeileDoc.elemente = zeileDoc.elemente || [];
        zeileDoc.elemente.push({ pos: `${String.fromCharCode(65 + a.z)}${nr}`, vorlage: vorlagenCodes()[0] || '', breite: 600 });
        S.auswahl = { typ: 'zeile', z: a.z };
        geaendert(true); sel('element', a.z, zeileDoc.elemente.length - 1);
      } }),
      h('button', { text: 'Zeile löschen', onclick: () => { doc.zeilen.splice(a.z, 1); S.auswahl = { typ: 'projekt' }; geaendert(true); renderSeitenleiste(); renderDetail(); } })
    ]), objektEditor(S.schemas['zeile.schema.json'], 'zeile.schema.json', zeileDoc, ['zeilen', a.z], { ...opts, ausser: ['elemente'] }));
  } else if (a.typ === 'element') {
    elementDetail(a.z, a.e, opts);
  }
}

async function elementDetail(z, e, opts) {
  const doc = S.projekt.doc;
  const liste = doc.zeilen[z].elemente;
  const inst = liste[e];
  const d = $('#detail');
  if (!inst) return;
  const pfad = ['zeilen', z, 'elemente', e];
  const verschiebe = dx => {
    const j = e + dx;
    if (j < 0 || j >= liste.length) return;
    [liste[e], liste[j]] = [liste[j], liste[e]];
    S.auswahl = { typ: 'element', z, e: j };
    geaendert(true); renderSeitenleiste(); renderDetail();
  };
  const [is, idat] = schemaVon(REF.instanz);
  const vorlagenFeld = (k, wert, p) => zeile('vorlage', is.properties.vorlage, true, (() => {
    const sel = h('select', { 'data-pfad': pfadText(p) }, [...new Set([...vorlagenCodes(), wert.vorlage].filter(Boolean))]
      .map(c => h('option', { value: c, text: `${c} – ${(S.katalog.vorlagen.find(v => v.code === c) || {}).name || '?'}` })));
    sel.value = wert.vorlage || '';
    sel.addEventListener('change', () => { wert.vorlage = sel.value; geaendert(); renderSeitenleiste(); renderDetail(); });
    return sel;
  })());
  d.replaceChildren(
    kopfMitAktionen(`Element ${inst.pos || ''} (${inst.vorlage || '?'})`, [
      h('button', { text: '◀ nach links', disabled: e === 0, onclick: () => verschiebe(-1) }),
      h('button', { text: 'nach rechts ▶', disabled: e === liste.length - 1, onclick: () => verschiebe(1) }),
      h('button', { text: '⧉ Duplizieren', onclick: () => { const k = klon(inst); k.pos = ''; liste.splice(e + 1, 0, k); S.auswahl = { typ: 'element', z, e: e + 1 }; geaendert(true); renderSeitenleiste(); renderDetail(); } }),
      h('button', { text: 'Löschen', onclick: () => { liste.splice(e, 1); S.auswahl = { typ: 'zeile', z }; geaendert(true); renderSeitenleiste(); renderDetail(); } })
    ]),
    objektEditor(is, idat, inst, pfad, { ...opts, ausser: ['overrides'], ersetze: { vorlage: vorlagenFeld } }),
    h('div', { id: 'anpassung' }, h('div', { class: 'hinweis', text: 'Lade Vorlage …' }))
  );
  const token = (S.token = (S.token || 0) + 1);
  const t = await vorlageHolen(inst.vorlage);
  if (token !== S.token || !$('#anpassung')) return;
  $('#anpassung').replaceChildren(anpassungen(inst, t, pfad));
  const hd = S.projekt;
  if (hd) markiereFelder(hd);
}

function tiefer(obj, pfad) { return pfad.split('.').reduce((o, k) => (o ? o[k] : undefined), obj); }

// Pro Schrank angepasste Listen der Vorlage: werden als Override (Punkt-Pfad -> ganze Liste) gespeichert
function anpassungen(inst, t, pfad) {
  const box = h('div');
  const bereinige = () => { if (inst.overrides && Object.keys(inst.overrides).length === 0) delete inst.overrides; };
  box.append(h('h3', { text: 'Anpassung der Vorlage für diesen Schrank' }),
    h('div', { class: 'hinweis', text: 'Hier kann die Anzahl und Art der Teile geändert werden (z. B. mehrere Schubladen mit eigener Höhe), ohne die Vorlage im Katalog zu ändern.' }));
  if (!t) { box.append(h('div', { class: 'hinweis', text: 'Vorlage nicht gefunden.' })); return box; }
  for (const a of ANPASSBAR) {
    const vorlagenListe = tiefer(t, a.pfad);
    const hat = inst.overrides && a.pfad in inst.overrides;
    if (!hat && !Array.isArray(vorlagenListe)) continue;
    const arbeit = hat ? inst.overrides[a.pfad] : klon(vorlagenListe);
    const fs = h('fieldset', {}, h('legend', {}, a.titel, ' ', hat ? h('span', { class: 'badge', text: 'angepasst' }) : h('span', { class: 'hinweis', text: 'wie Vorlage' })));
    const listeSchema = { type: 'array', items: { $ref: a.ref } };
    const pf = [...pfad, 'overrides', ...a.pfad.split('.')];
    const opts = {
      geaendert: s => { inst.overrides = inst.overrides || {}; inst.overrides[a.pfad] = arbeit; geaendert(s); fs.querySelector('legend').replaceChildren(a.titel, ' ', h('span', { class: 'badge', text: 'angepasst' })); },
      listenKnoepfe: a.pfad === 'front.felder' ? (liste, neu) => ['schublade', 'tuer'].map(art => h('button', {
        text: art === 'schublade' ? '+ Schublade' : '+ Tür',
        onclick: () => {
          const vorlageFeld = [...liste].reverse().find(f => f.art === art);
          liste.push(vorlageFeld ? klon(vorlageFeld) : (art === 'schublade' ? { art, anteil: 1, beschlag: 'schubkastensystem' } : { art, anteil: 1, anschlag: 'rechts' }));
          neu();
        }
      })) : null
    };
    fs.append(listenEditor(listeSchema, 'vorlage.schema.json', arbeit, pf, opts));
    if (hat) {
      fs.append(h('button', {
        text: 'Auf Vorlage zurücksetzen', onclick: () => { delete inst.overrides[a.pfad]; bereinige(); geaendert(true); renderDetail(); }
      }));
    }
    box.append(fs);
  }
  // Alle übrigen Overrides (Punkt-Pfad -> Wert), z. B. "parameter.tiefe.default": 520
  const uebrige = h('fieldset', {}, h('legend', { text: 'Weitere Anpassungen (Pfad → Wert)' }));
  inst.overrides = inst.overrides || {};
  const ovBox = dictEditor({ propertyNames: { pattern: '^[a-z0-9_]+(\\.[a-z0-9_]+)*$' } }, 'zeile.schema.json', inst.overrides, [...pfad, 'overrides'],
    { verberge: ANPASSBAR.map(a => a.pfad), geaendert: s => { geaendert(s); } }, [], () => { renderDetail(); });
  uebrige.append(ovBox);
  box.append(uebrige);
  bereinige();
  return box;
}

async function projektWaehlen() {
  const r = await rpc('projekt_waehlen');
  if (r.abgebrochen) return;
  uebernehmeInit(r);
  renderAlles();
}

/* ---------- Katalog ---------- */
function katalogSeite(wurzel) {
  for (const [art, titel] of ARTEN) {
    const dateien = S.katalog.dateien.filter(f => f.art === art);
    const neue = Object.values(S.dokumente).filter(d => d.neu && d.art === art && !dateien.some(f => f.pfad === d.pfad));
    wurzel.append(h('div', { class: 'gruppe' }, h('span', { text: titel }), h('button', {
      class: 'klein', text: '+ Neu', onclick: () => { S.neuFormular = S.neuFormular === art ? null : art; renderSeitenleiste(); }
    })));
    if (S.neuFormular === art) wurzel.append(neuFormular(art));
    [...dateien.map(f => ({ ...f })), ...neue.map(d => ({ art, pfad: d.pfad, titel: d.pfad.split('/').pop().replace(/\.json$/, '') }))].forEach(f => {
      const k = knoten(f.titel, S.datei && S.datei.pfad === f.pfad, () => dateiOeffnen(f.pfad, f.art), 1);
      k.dataset.datei = f.pfad;
      wurzel.append(k);
    });
  }
}
function neuFormular(art) {
  const id = h('input', { type: 'text', placeholder: art === 'vorlage' ? 'Code, z. B. US-S4' : 'Kennung' });
  const basis = art === 'vorlage' ? h('select', {}, [h('option', { value: '', text: '(keine Basis)' }), ...S.katalog.vorlagen.map(v => h('option', { value: v.code, text: `Basis ${v.code}` }))]) : null;
  const ok = async () => {
    const r = await rpc('neu', { art, id: id.value, basis: basis ? basis.value : undefined });
    if (r.fehler_text) { status(r.fehler_text, 'fehler'); return; }
    S.dokumente[r.pfad] = neuerHalter(r.pfad, r.art, r.doc, true);
    S.neuFormular = null;
    dateiOeffnen(r.pfad, r.art);
  };
  return h('div', { class: 'neu' }, id, basis, h('button', { text: 'Anlegen', onclick: ok }));
}
async function dateiOeffnen(pfad, art) {
  if (!S.dokumente[pfad]) {
    const r = await rpc('datei_laden', { pfad });
    if (r.fehler_text) { status(r.fehler_text, 'fehler'); return; }
    S.dokumente[pfad] = neuerHalter(pfad, r.art || art, r.doc, false);
  }
  S.datei = S.dokumente[pfad];
  renderSeitenleiste();
  renderDetail();
}
function katalogDetail() {
  const d = $('#detail');
  d.replaceChildren();
  const hd = S.datei;
  if (!hd) { d.append(h('div', { class: 'leer', text: 'Datei links auswählen oder neu anlegen.' })); return; }
  const schema = S.schemas[`${hd.art}.schema.json`];
  d.append(kopfMitAktionen(hd.pfad.split('/').slice(-2).join('/'), h('span', { class: 'hinweis', text: hd.neu ? 'Neu, noch nicht gespeichert' : hd.pfad })));
  const opts = { vorschlaege: { basis: S.katalog.vorlagen.map(v => v.code) } };
  if (hd.art === 'regeldatei') d.append(listenEditor(schema, `${hd.art}.schema.json`, hd.doc, [], opts));
  else d.append(objektEditor(schema, `${hd.art}.schema.json`, hd.doc, [], opts));
  markiereFelder(hd);
}

/* ---------- Aufbau ---------- */
function renderSeitenleiste() {
  const a = $('#seitenleiste');
  a.replaceChildren();
  const baum = h('div', { class: 'baum' });
  if (S.tab === 'projekt') projektSeite(baum); else katalogSeite(baum);
  a.append(baum);
  markiereBaum();
}
function renderDetail() {
  if (S.tab === 'projekt') projektDetail(); else katalogDetail();
  const hd = halter();
  if (hd) anzeigeFehler(hd); else $('#fehlerliste').hidden = true;
}
function renderAlles() { renderSeitenleiste(); renderDetail(); }

function uebernehmeInit(r) {
  S.schemas = r.schemas || S.schemas;
  S.katalog = r.katalog || S.katalog;
  S.vorlagenCache = {};
  if (r.projekt) S.projekt = neuerHalter(r.projekt.pfad, 'projekt', r.projekt.doc, false);
  S.auswahl = { typ: 'projekt' };
}

function verdrahten() {
  document.querySelectorAll('button.tab').forEach(b => b.addEventListener('click', () => {
    S.tab = b.dataset.tab;
    document.querySelectorAll('button.tab').forEach(x => x.classList.toggle('aktiv', x === b));
    renderAlles();
  }));
  $('#live').addEventListener('change', e => {
    S.live = e.target.checked;
    status(S.live ? 'Live: Änderungen werden sofort übernommen' : '', '');
    const hd = halter();
    if (S.live && hd && hd.dirty) speichere(hd, true);
  });
  $('#uebernehmen').addEventListener('click', () => { const hd = halter(); if (hd) speichere(hd, true); });
  $('#rueckgaengig').addEventListener('click', () => {
    const hd = halter();
    if (!hd || !hd.undo.length) return;
    hd.stand = hd.undo.pop();
    hd.doc = JSON.parse(hd.stand);
    hd.dirty = true;
    renderAlles();
    plane(hd);
  });
}

async function start() {
  verdrahten();
  const r = await rpc('init');
  if (r.fehler_text) { status(r.fehler_text, 'fehler'); return; }
  uebernehmeInit(r);
  renderAlles();
  if (S.projekt) pruefe(S.projekt);
}
window.__kp = S; // zum Prüfen in Tests
window.addEventListener('DOMContentLoaded', start);
