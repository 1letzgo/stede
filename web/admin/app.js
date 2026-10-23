// stede Admin: Tenant-Admins pflegen Orte, Termine, Veranstalter, Gruppen und tenants.config.
// Schreibrechte kommen allein aus RLS (Migration web_admin_policies), im Browser liegt nur der Publishable Key.
"use strict";

const cfg = window.STEDE_CONFIG;
const sb = supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey, {
  auth: { flowType: "pkce", detectSessionInUrl: true, persistSession: true },
});

const $ = (sel) => document.querySelector(sel);
const TZ = "Europe/Berlin";
const DIRECTORIES = {
  gastro: "Gastro", health: "Gesundheit", leisure: "Freizeit & Sport", sights: "Sehenswürdigkeiten",
  playgrounds: "Spiel & Spaß", trips: "Ausflüge", bikes: "Fahrrad", volunteer: "Ehrenamtskarte",
};
const FEATURES = {
  weather: "Wetter", calendar: "Kalender", train: "Bahn", bus: "Bus", waste: "Abfuhr", ferry: "Fähre",
  tides: "Gezeiten", air: "Luft", groups: "Gruppen", plus: "plus", politics: "Politik",
};

const state = { user: null, tenants: [], tenant: null, tab: "places", placesDir: "gastro", eventsFrom: startOfToday() };

// ---------- Hilfen ----------

function esc(v) {
  return String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function toast(msg, isError = false) {
  const t = $("#toast");
  t.textContent = msg;
  t.className = isError ? "err" : "";
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), isError ? 6000 : 2500);
}

async function run(promise) {
  const { data, error } = await promise;
  if (error) { toast(error.message, true); throw error; }
  return data;
}

function berlinParts(d) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(d);
  return Object.fromEntries(parts.map((p) => [p.type, p.value]));
}

// ISO → "YYYY-MM-DDTHH:mm" in Inselzeit (Europe/Berlin), unabhängig von der Zeitzone des Browsers
function toLocalInput(iso) {
  if (!iso) return "";
  const p = berlinParts(new Date(iso));
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}

function fromLocalInput(s) {
  if (!s) return null;
  const [d, t = "00:00"] = s.split("T");
  const [y, m, day] = d.split("-").map(Number);
  const [h, mi] = t.split(":").map(Number);
  const wanted = Date.UTC(y, m - 1, day, h, mi);
  let guess = wanted;
  for (let i = 0; i < 2; i++) {
    const p = berlinParts(new Date(guess));
    guess += wanted - Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute);
  }
  return new Date(guess).toISOString();
}

function startOfToday() {
  return fromLocalInput(toLocalInput(new Date().toISOString()).slice(0, 10) + "T00:00");
}

function addDays(iso, days) {
  const local = toLocalInput(iso).slice(0, 10);
  const d = new Date(local + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  return fromLocalInput(d.toISOString().slice(0, 10) + "T00:00");
}

function fmt(iso, withTime = true) {
  if (!iso) return "";
  return new Intl.DateTimeFormat("de-DE", {
    timeZone: TZ, weekday: "short", day: "2-digit", month: "2-digit", year: "numeric",
    ...(withTime ? { hour: "2-digit", minute: "2-digit" } : {}),
  }).format(new Date(iso));
}

function photoURL(path) {
  if (!path) return null;
  if (/^https?:/.test(path)) return path;
  if (path.startsWith("content/")) return `${cfg.supabaseUrl}/storage/v1/object/public/${path}`;
  return `${cfg.supabaseUrl}/storage/v1/object/public/event-photos/${path}`;
}

function randomID(n = 10) {
  return [...crypto.getRandomValues(new Uint8Array(n))].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, n);
}

// ---------- Editor-Dialog ----------

// fields: [{key, label, type: text|textarea|number|check|datetime|date|select|list, options, full, hint}]
function openEditor({ title, fields, values, hint, extra = "", buttons = [], onSave }) {
  const form = $("#editor-form");
  const input = (f) => {
    const v = values[f.key];
    const name = `name="${f.key}"`;
    switch (f.type) {
      case "textarea": return `<textarea ${name}>${esc(v)}</textarea>`;
      case "number": return `<input ${name} type="number" step="any" value="${esc(v)}">`;
      case "datetime": return `<input ${name} type="datetime-local" value="${esc(toLocalInput(v))}">`;
      case "date": return `<input ${name} type="date" value="${esc(toLocalInput(v).slice(0, 10))}">`;
      case "list": return `<input ${name} value="${esc((v || []).join(", "))}">`;
      case "select": return `<select ${name}>${f.options.map(([k, l]) => `<option value="${esc(k)}" ${k === (v ?? "") ? "selected" : ""}>${esc(l)}</option>`).join("")}</select>`;
      default: return `<input ${name} value="${esc(v)}" ${f.datalist ? `list="dl-${f.key}"` : ""}>` +
        (f.datalist ? `<datalist id="dl-${f.key}">${f.datalist.map((o) => `<option value="${esc(o)}">`).join("")}</datalist>` : "");
    }
  };
  form.innerHTML = `
    <h3>${esc(title)}</h3>
    ${hint ? `<div class="hint">${hint}</div>` : ""}
    <div class="grid">
      ${fields.map((f) => f.type === "check"
        ? `<label class="check ${f.full ? "full" : ""}"><input type="checkbox" name="${f.key}" ${values[f.key] ? "checked" : ""}> ${esc(f.label)}</label>`
        : `<label class="${f.full ? "full" : ""}">${esc(f.label)}${input(f)}${f.hint ? `<small>${esc(f.hint)}</small>` : ""}</label>`).join("")}
      ${extra}
    </div>
    <div class="actions">
      <span class="left">${buttons.map((b, i) => `<button type="button" class="${b.cls || "ghost"}" data-btn="${i}">${esc(b.label)}</button>`).join("")}</span>
      <button type="button" class="ghost" data-close>Abbrechen</button>
      <button type="submit" value="save">Speichern</button>
    </div>`;
  const dialog = $("#editor");
  const collect = () => {
    const out = {};
    for (const f of fields) {
      const el = form.elements[f.key];
      if (f.type === "check") out[f.key] = el.checked;
      else if (f.type === "number") out[f.key] = el.value === "" ? null : Number(el.value);
      else if (f.type === "datetime") out[f.key] = fromLocalInput(el.value);
      else if (f.type === "date") out[f.key] = el.value ? fromLocalInput(el.value + "T00:00") : null;
      else if (f.type === "list") { const l = el.value.split(",").map((s) => s.trim()).filter(Boolean); out[f.key] = l.length ? l : null; }
      else { const s = el.value.trim(); out[f.key] = s === "" ? null : s; }
    }
    return out;
  };
  form.querySelector("[data-close]").onclick = () => dialog.close();
  buttons.forEach((b, i) => (form.querySelector(`[data-btn="${i}"]`).onclick = async () => {
    if (b.confirm && !confirm(b.confirm)) return;
    try { await b.onClick(collect(), form); dialog.close(); } catch (e) { console.error(e); }
  }));
  form.onsubmit = async (e) => {
    e.preventDefault();
    try { await onSave(collect(), form); dialog.close(); } catch (err) { console.error(err); }
  };
  dialog.showModal();
  return form;
}

// ---------- Anmeldung ----------

async function start() {
  const { data } = await sb.auth.getSession();
  await setSession(data.session);
  sb.auth.onAuthStateChange((_e, session) => {
    if ((session?.user?.id ?? null) !== (state.user?.id ?? null)) setSession(session);
  });
}

async function setSession(session) {
  state.user = session?.user ?? null;
  $("#login").hidden = !!state.user;
  $("#logout").hidden = !state.user;
  $("#who").textContent = state.user?.email ?? "";
  if (!state.user) { $("#app").hidden = true; $("#noadmin").hidden = true; $("#tenant").hidden = true; return; }

  const admins = await run(sb.from("tenant_admins").select("tenant_id").eq("user_id", state.user.id));
  const ids = admins.map((a) => a.tenant_id);
  state.tenants = ids.length ? await run(sb.from("tenants").select("*").in("id", ids).order("name")) : [];
  $("#noadmin").hidden = state.tenants.length > 0;
  $("#app").hidden = state.tenants.length === 0;
  if (!state.tenants.length) return;

  const saved = localStorage.getItem("admin.tenant");
  state.tenant = state.tenants.find((t) => t.slug === saved) ?? state.tenants[0];
  const sel = $("#tenant");
  sel.innerHTML = state.tenants.map((t) => `<option value="${t.slug}">${esc(t.name)}</option>`).join("");
  sel.value = state.tenant.slug;
  sel.hidden = state.tenants.length < 2;
  render();
}

$("#login-form").onsubmit = async (e) => {
  e.preventDefault();
  const email = $("#email").value.trim();
  const { error } = await sb.auth.signInWithOtp({ email, options: { emailRedirectTo: location.origin + location.pathname } });
  $("#login-msg").textContent = error ? error.message : "Link ist unterwegs – bitte im selben Browser öffnen.";
};
$("#logout").onclick = () => sb.auth.signOut();
$("#tenant").onchange = (e) => {
  state.tenant = state.tenants.find((t) => t.slug === e.target.value);
  localStorage.setItem("admin.tenant", state.tenant.slug);
  render();
};
document.querySelectorAll(".tabs button").forEach((b) => (b.onclick = () => {
  state.tab = b.dataset.tab;
  document.querySelectorAll(".tabs button").forEach((x) => x.classList.toggle("active", x === b));
  render();
}));

function render() {
  const view = $("#view");
  view.innerHTML = `<p class="muted">Lädt …</p>`;
  ({ places: renderPlaces, events: renderEvents, organizers: renderOrganizers, groups: renderGroups, config: renderConfig })[state.tab](view)
    .catch((e) => { console.error(e); view.innerHTML = `<p class="muted">Fehler: ${esc(e.message)}</p>`; });
}

// ---------- Orte ----------

async function renderPlaces(view) {
  const t = state.tenant;
  const rows = await run(sb.from("places").select("*").eq("tenant_id", t.id).eq("directory", state.placesDir).order("sort_order").order("name"));
  const kinds = [...new Set(rows.map((r) => r.kind).filter(Boolean))].sort();
  view.innerHTML = `
    <div class="toolbar">
      <select id="p-dir">${Object.entries(DIRECTORIES).map(([k, l]) => `<option value="${k}" ${k === state.placesDir ? "selected" : ""}>${l}</option>`).join("")}</select>
      <select id="p-kind"><option value="">Alle Arten</option>${kinds.map((k) => `<option>${esc(k)}</option>`).join("")}</select>
      <input id="p-q" type="search" placeholder="Suchen …">
      <label class="check"><input type="checkbox" id="p-gone"> Ausgeblendete zeigen</label>
      <span class="spacer"></span>
      <button id="p-new">Neuer Ort</button>
    </div>
    <table><thead><tr><th>Name</th><th>Art</th><th class="hide-sm">Adresse</th><th class="hide-sm">Geändert</th></tr></thead><tbody id="p-rows"></tbody></table>`;
  const draw = () => {
    const q = $("#p-q").value.toLowerCase(), kind = $("#p-kind").value, gone = $("#p-gone").checked;
    const list = rows.filter((r) => (gone || !r.deleted_at) && (!kind || r.kind === kind) &&
      (!q || [r.name, r.street, r.teaser].some((s) => s?.toLowerCase().includes(q))));
    $("#p-rows").innerHTML = list.map((r) => `
      <tr data-id="${r.id}" class="${r.deleted_at ? "gone" : ""}">
        <td>${esc(r.name)} ${r.image_path ? '<span class="pill blue">Foto</span>' : ""} ${(r.features || []).map((f) => `<span class="pill">${esc(f)}</span>`).join("")}</td>
        <td>${esc(r.kind)}</td><td class="hide-sm">${esc(r.street)}</td><td class="hide-sm">${fmt(r.updated_at, false)}</td>
      </tr>`).join("") || `<tr><td colspan="4" class="muted">Keine Einträge</td></tr>`;
    $("#p-rows").querySelectorAll("tr[data-id]").forEach((tr) => (tr.onclick = () => editPlace(rows.find((r) => r.id === tr.dataset.id), kinds)));
  };
  $("#p-dir").onchange = (e) => { state.placesDir = e.target.value; render(); };
  ["#p-q", "#p-kind", "#p-gone"].forEach((s) => ($(s).oninput = draw));
  $("#p-new").onclick = () => editPlace(null, kinds);
  draw();
}

function editPlace(place, kinds) {
  const t = state.tenant;
  const values = place ?? { directory: state.placesDir, sort_order: 0 };
  let imagePath = values.image_path ?? null;
  const fields = [
    { key: "name", label: "Name", full: true },
    { key: "kind", label: "Art", datalist: kinds },
    { key: "sort_order", label: "Sortierung", type: "number" },
    { key: "teaser", label: "Kurzbeschreibung", type: "textarea", full: true },
    { key: "street", label: "Adresse" },
    { key: "phone", label: "Telefon" },
    { key: "email", label: "E-Mail" },
    { key: "website", label: "Website" },
    { key: "hours", label: "Öffnungszeiten", type: "textarea", full: true },
    { key: "rest_day", label: "Ruhetag" },
    { key: "season_note", label: "Saison-Hinweis" },
    { key: "features", label: "Merkmale (Komma-getrennt, z. B. Lieferdienst)", type: "list", full: true },
    { key: "extra_link_title", label: "Zusatzlink: Titel" },
    { key: "extra_link_url", label: "Zusatzlink: URL" },
    { key: "lat", label: "Breite (lat)", type: "number" },
    { key: "lon", label: "Länge (lon)", type: "number" },
    { key: "image_credit", label: "Foto-Nachweis", full: true },
  ];
  const photoBlock = () => imagePath
    ? `<img class="photo" src="${photoURL("content/" + imagePath)}" alt=""><button type="button" class="ghost small" id="ph-remove">Foto entfernen</button>`
    : `<span class="muted">Kein Foto</span>`;
  const extra = `<div class="full"><label>Foto</label><div id="ph">${photoBlock()}</div><input type="file" id="ph-file" accept="image/jpeg,image/png,image/webp"></div>`;
  const buttons = place ? [place.deleted_at
    ? { label: "Wieder einblenden", cls: "ok", onClick: () => savePlace({ deleted_at: null }) }
    : { label: "Ausblenden", cls: "danger", confirm: "Ort in den Apps ausblenden?", onClick: () => savePlace({ deleted_at: new Date().toISOString() }) }] : [];

  async function savePlace(patch) {
    if (place) await run(sb.from("places").update(patch).eq("id", place.id));
    else await run(sb.from("places").insert({ ...patch, tenant_id: t.id, directory: state.placesDir, external_id: `web-${randomID()}`, status: "published" }));
    toast("Gespeichert – die Apps holen es beim nächsten Start.");
    render();
  }

  const form = openEditor({
    title: place ? place.name : `Neuer Ort · ${DIRECTORIES[state.placesDir]}`,
    fields, values, extra, buttons,
    onSave: (v) => {
      if (!v.name) { toast("Name fehlt", true); throw new Error("Name fehlt"); }
      return savePlace({ ...v, sort_order: v.sort_order ?? 0, image_path: imagePath });
    },
  });
  const bindRemove = () => { const b = form.querySelector("#ph-remove"); if (b) b.onclick = () => { imagePath = null; form.querySelector("#ph").innerHTML = photoBlock(); }; };
  bindRemove();
  form.querySelector("#ph-file").onchange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const ext = { "image/png": "png", "image/webp": "webp" }[file.type] ?? "jpg";
    const path = `${t.slug}/places/${state.placesDir}-web-${randomID(12)}.${ext}`;
    await run(sb.storage.from("content").upload(path, file, { contentType: file.type, cacheControl: "31536000" }));
    imagePath = path;
    form.querySelector("#ph").innerHTML = photoBlock();
    bindRemove();
    toast("Foto hochgeladen – mit Speichern übernehmen.");
  };
}

// ---------- Termine ----------

async function renderEvents(view) {
  const t = state.tenant;
  const from = state.eventsFrom, to = addDays(from, 30);
  const groups = await run(sb.from("communities").select("id").eq("tenant_id", t.id));
  const cols = "*, communities(name)";
  const [targeted, home] = await Promise.all([
    run(sb.from("community_events").select(cols).contains("target_tenants", [t.id]).gte("starts_at", from).lt("starts_at", to).order("starts_at").limit(2000)),
    groups.length ? run(sb.from("community_events").select(cols).in("community_id", groups.map((g) => g.id)).gte("starts_at", from).lt("starts_at", to).order("starts_at").limit(2000)) : [],
  ]);
  const byID = new Map([...targeted, ...home].map((e) => [e.id, e]));
  const rows = [...byID.values()].sort((a, b) => a.starts_at.localeCompare(b.starts_at));

  view.innerHTML = `
    <div class="toolbar">
      <button class="ghost small" id="e-prev">‹ 30 Tage</button>
      <strong>${fmt(from, false)} – ${fmt(addDays(to, -1), false)}</strong>
      <button class="ghost small" id="e-next">30 Tage ›</button>
      <button class="ghost small" id="e-today">Heute</button>
      <input id="e-q" type="search" placeholder="Titel, Ort, Veranstalter …">
      <select id="e-src"><option value="">Alle</option><option value="import">Importiert</option><option value="app">Aus der App</option></select>
      <label class="check"><input type="checkbox" id="e-cancel"> Abgesagte zeigen</label>
    </div>
    <table><thead><tr><th>Wann</th><th>Titel</th><th class="hide-sm">Ort</th><th class="hide-sm">Gruppe / Veranstalter</th></tr></thead><tbody id="e-rows"></tbody></table>`;
  const draw = () => {
    const q = $("#e-q").value.toLowerCase(), src = $("#e-src").value, cancelled = $("#e-cancel").checked;
    const list = rows.filter((e) => (cancelled || !e.cancelled_at) &&
      (!src || (src === "import") === !!e.external_key) &&
      (!q || [e.title, e.location, e.organizer, e.category].some((s) => s?.toLowerCase().includes(q))));
    $("#e-rows").innerHTML = list.map((e) => `
      <tr data-id="${e.id}" class="${e.cancelled_at ? "gone" : ""}">
        <td>${fmt(e.starts_at, !e.all_day)}${e.all_day ? ' <span class="pill">ganztägig</span>' : ""}</td>
        <td>${esc(e.title)}
          ${e.external_key ? '<span class="pill blue">Import</span>' : ""}
          ${e.external_locked ? '<span class="pill amber">gesperrt</span>' : ""}
          ${e.visibility === "members" ? '<span class="pill">intern</span>' : ""}
          ${e.sold_out ? '<span class="pill red">ausgebucht</span>' : ""}</td>
        <td class="hide-sm">${esc(e.location)}</td>
        <td class="hide-sm">${esc(e.communities?.name)}${e.organizer ? `<br><span class="muted">${esc(e.organizer)}</span>` : ""}</td>
      </tr>`).join("") || `<tr><td colspan="4" class="muted">Keine Termine in diesem Zeitraum</td></tr>`;
    $("#e-rows").querySelectorAll("tr[data-id]").forEach((tr) => (tr.onclick = () => editEvent(byID.get(tr.dataset.id))));
  };
  $("#e-prev").onclick = () => { state.eventsFrom = addDays(from, -30); render(); };
  $("#e-next").onclick = () => { state.eventsFrom = to; render(); };
  $("#e-today").onclick = () => { state.eventsFrom = startOfToday(); render(); };
  ["#e-q", "#e-src", "#e-cancel"].forEach((s) => ($(s).oninput = draw));
  draw();
}

function editEvent(ev) {
  const fields = [
    { key: "title", label: "Titel", full: true },
    { key: "all_day", label: "Ganztägig", type: "check", full: true },
    { key: "starts_at", label: "Beginn", type: "datetime" },
    { key: "ends_at", label: "Ende", type: "datetime" },
    { key: "location", label: "Ort" },
    { key: "category", label: "Kategorie" },
    { key: "description", label: "Beschreibung", type: "textarea", full: true },
    { key: "organizer", label: "Veranstalter (Text)" },
    { key: "price", label: "Preis" },
    { key: "registration", label: "Anmeldung" },
    { key: "source_url", label: "Quelle (URL)" },
    { key: "image_credit", label: "Foto-Nachweis", full: true },
    { key: "visibility", label: "Sichtbarkeit", type: "select", options: [["public", "Öffentlich"], ["members", "Nur Mitglieder"]] },
    { key: "sold_out", label: "Ausgebucht", type: "check" },
    { key: "rsvp_enabled", label: "Teilnahme abfragen", type: "check" },
    { key: "comments_enabled", label: "Kommentare erlauben", type: "check" },
  ];
  if (ev.external_key) fields.push({ key: "external_locked", label: "Vor dem Import geschützt (Änderungen der Quelle werden nicht übernommen)", type: "check", full: true });
  const hint = ev.external_key
    ? `Importiert aus ${esc(ev.source_name || "der Gemeinde-Quelle")}. Inhaltliche Änderungen sperren den Termin für den Import.`
    : "";
  const img = photoURL(ev.image_path);
  const extra = img ? `<div class="full"><img class="photo" src="${esc(img)}" alt=""></div>` : "";
  const update = async (patch, msg = "Gespeichert") => {
    await run(sb.from("community_events").update(patch).eq("id", ev.id));
    toast(msg);
    render();
  };
  const buttons = [
    ev.cancelled_at
      ? { label: "Absage zurücknehmen", cls: "ok", onClick: () => update({ cancelled_at: null }, "Termin wieder aktiv") }
      : { label: "Absagen", cls: "danger", confirm: "Termin absagen?", onClick: () => update({ cancelled_at: new Date().toISOString() }, "Termin abgesagt") },
    { label: "Löschen", cls: "danger", confirm: "Termin endgültig löschen? Teilnahmen und Kommentare gehen verloren." + (ev.external_key && !ev.external_locked ? " Der Import legt ihn beim nächsten Lauf wieder an – Absagen ist meist besser." : ""),
      onClick: async () => { await run(sb.from("community_events").delete().eq("id", ev.id)); toast("Gelöscht"); render(); } },
  ];
  const form = openEditor({
    title: ev.title, fields, values: ev, hint, extra, buttons,
    onSave: (v) => {
      if (v.all_day && v.starts_at) v.starts_at = fromLocalInput(toLocalInput(v.starts_at).slice(0, 10) + "T00:00");
      if (!v.title || !v.starts_at) { toast("Titel und Beginn sind Pflicht", true); throw new Error("Pflichtfeld"); }
      return update(v);
    },
  });
  // Ganztägig: Beginn als reines Datum (fromLocalInput ergänzt 00:00)
  const start = form.elements.starts_at;
  form.elements.all_day.onchange = (e) => {
    const day = start.value.slice(0, 10);
    start.type = e.target.checked ? "date" : "datetime-local";
    start.value = e.target.checked ? day : day && day + "T00:00";
  };
  if (ev.all_day) { start.type = "date"; start.value = toLocalInput(ev.starts_at).slice(0, 10); }
}

// ---------- Veranstalter ----------

async function renderOrganizers(view) {
  const t = state.tenant;
  const [rows, groups] = await Promise.all([
    run(sb.from("organizers").select("*").eq("tenant_id", t.id).order("name")),
    run(sb.from("communities").select("id, name").order("name")),
  ]);
  const groupName = Object.fromEntries(groups.map((g) => [g.id, g.name]));
  view.innerHTML = `
    <div class="toolbar"><input id="o-q" type="search" placeholder="Veranstalter suchen …"><span class="muted">${rows.length} Veranstalter</span></div>
    <table><thead><tr><th>Name</th><th class="hide-sm">Website</th><th>Gruppe</th></tr></thead><tbody id="o-rows"></tbody></table>`;
  const draw = () => {
    const q = $("#o-q").value.toLowerCase();
    $("#o-rows").innerHTML = rows.filter((o) => !q || o.name.toLowerCase().includes(q)).map((o) => `
      <tr data-id="${o.id}"><td>${esc(o.name)}</td><td class="hide-sm">${esc(o.website)}</td>
      <td>${o.community_id ? `<span class="pill green">${esc(groupName[o.community_id] ?? "Gruppe")}</span>` : '<span class="muted">Sammelgruppe</span>'}</td></tr>`).join("");
    $("#o-rows").querySelectorAll("tr").forEach((tr) => (tr.onclick = () => {
      const o = rows.find((r) => r.id === tr.dataset.id);
      openEditor({
        title: o.name,
        hint: "Der Name ist nur die Anzeige; die Zuordnung zum Import bleibt erhalten. Termine an eine Gruppe übertragen geht in der App („An Gruppe übertragen“).",
        fields: [{ key: "name", label: "Name", full: true }, { key: "website", label: "Website", full: true }],
        values: o,
        onSave: async (v) => {
          if (!v.name) { toast("Name fehlt", true); throw new Error("Name fehlt"); }
          await run(sb.from("organizers").update(v).eq("id", o.id));
          toast("Gespeichert");
          render();
        },
      });
    }));
  };
  $("#o-q").oninput = draw;
  draw();
}

// ---------- Gruppen-Moderation ----------

async function renderGroups(view) {
  const t = state.tenant;
  const rows = await run(sb.from("v_community_overview").select("*").eq("tenant_id", t.id).order("created_at", { ascending: false }));
  const pending = rows.filter((g) => g.status === "pending");
  const others = rows.filter((g) => g.status !== "pending");
  const statusPill = { approved: '<span class="pill green">freigegeben</span>', rejected: '<span class="pill red">abgelehnt</span>', archived: '<span class="pill">archiviert</span>' };
  const card = (g, actions) => `
    <div class="card row">
      <div class="grow"><strong>${esc(g.name)}</strong> ${statusPill[g.status] ?? ""} ${g.countywide ? '<span class="pill blue">Kreisweit</span>' : ""}
        ${g.visibility === "hidden" ? '<span class="pill">versteckt</span>' : ""}
        <div class="muted">${esc(g.description)}</div>
        <small class="muted">${g.member_count ?? 0} Mitglieder · angelegt ${fmt(g.created_at, false)}</small></div>
      ${actions}
    </div>`;
  view.innerHTML = `
    <h2>Warten auf Freigabe (${pending.length})</h2>
    <div class="list">${pending.map((g) => card(g, `<button class="ok small" data-ok="${g.id}">Freigeben</button><button class="danger small" data-no="${g.id}">Ablehnen</button>`)).join("") || '<p class="muted">Nichts offen.</p>'}</div>
    <h2>Alle Gruppen</h2>
    <div class="list">${others.map((g) => card(g, "")).join("")}</div>`;
  const setStatus = async (id, status) => {
    await run(sb.from("communities").update({ status }).eq("id", id));
    toast(status === "approved" ? "Gruppe freigegeben" : "Gruppe abgelehnt");
    render();
  };
  view.querySelectorAll("[data-ok]").forEach((b) => (b.onclick = () => setStatus(b.dataset.ok, "approved")));
  view.querySelectorAll("[data-no]").forEach((b) => (b.onclick = () => confirm("Gruppe ablehnen?") && setStatus(b.dataset.no, "rejected")));
}

// ---------- Konfiguration ----------

async function renderConfig(view) {
  const t = (await run(sb.from("tenants").select("*").eq("id", state.tenant.id)))[0];
  const config = t.config ?? {};
  const features = config.features ?? {};
  const places = new Set(features.places ?? []);
  view.innerHTML = `
    <div class="card">
      <div class="grid">
        <label>Name<input id="c-name" value="${esc(t.name)}"></label>
        <label>Gemeinde<input id="c-mun" value="${esc(t.municipality)}"></label>
        <label>Mitte (lat)<input id="c-lat" type="number" step="any" value="${esc(t.center_lat)}"></label>
        <label>Mitte (lon)<input id="c-lon" type="number" step="any" value="${esc(t.center_lon)}"></label>
      </div>
      <h2>Bausteine</h2>
      <p class="muted">Gilt nur, soweit die App-Marke den Baustein kennt. Ohne <code>features</code> nutzt die App ihre Standardwerte.</p>
      <div class="toolbar">${Object.entries(FEATURES).map(([k, l]) => `<label class="check"><input type="checkbox" data-f="${k}" ${features[k] ? "checked" : ""}> ${l}</label>`).join("")}</div>
      <h2>Verzeichnisse</h2>
      <div class="toolbar">${Object.entries(DIRECTORIES).map(([k, l]) => `<label class="check"><input type="checkbox" data-d="${k}" ${places.has(k) ? "checked" : ""}> ${l}</label>`).join("")}</div>
      <h2>config (JSON)</h2>
      <p class="muted">Kennung <code>${esc(t.slug)}</code>, Region <code>${esc(t.region)}</code> – beide fest. Änderungen wirken beim nächsten App-Start.</p>
      <textarea id="c-json" class="code" spellcheck="false">${esc(JSON.stringify(config, null, 2))}</textarea>
      <div class="actions"><button id="c-save">Speichern</button></div>
    </div>`;
  const parse = () => { try { return JSON.parse($("#c-json").value); } catch { return null; } };
  const syncBoxes = () => {
    const c = parse();
    if (!c) return toast("JSON ist ungültig", true);
    c.features = c.features ?? {};
    view.querySelectorAll("[data-f]").forEach((b) => { if (b.checked) c.features[b.dataset.f] = true; else delete c.features[b.dataset.f]; });
    c.features.places = [...view.querySelectorAll("[data-d]")].filter((b) => b.checked).map((b) => b.dataset.d);
    $("#c-json").value = JSON.stringify(c, null, 2);
  };
  view.querySelectorAll("[data-f], [data-d]").forEach((b) => (b.onchange = syncBoxes));
  $("#c-save").onclick = async () => {
    const c = parse();
    if (!c) return toast("JSON ist ungültig", true);
    const num = (s) => ($(s).value === "" ? null : Number($(s).value));
    await run(sb.from("tenants").update({
      name: $("#c-name").value.trim(), municipality: $("#c-mun").value.trim() || null,
      center_lat: num("#c-lat"), center_lon: num("#c-lon"), config: c,
    }).eq("id", t.id));
    state.tenant = { ...state.tenant, name: $("#c-name").value.trim(), config: c };
    toast("Konfiguration gespeichert");
  };
}

start();
