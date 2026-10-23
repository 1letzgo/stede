// Nutzerverwaltung für das Web-Admin (web/admin): nur für Hauptadmins (bootstrap_admins).
// Aufruf mit dem Nutzer-JWT als POST {action, ...}; die Service-Rolle liest auth.users
// und schreibt tenant_admins, profiles und Sperren. verify_jwt ist aus, damit der
// CORS-Preflight durchkommt – die Prüfung macht die Funktion selbst.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user?.email) return json({ error: "Nicht angemeldet" }, 401);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: boot } = await admin.from("bootstrap_admins").select("email");
  const superEmails = new Set((boot ?? []).map((b) => b.email.toLowerCase()));
  const isSuper = superEmails.has(user.email.toLowerCase());

  const body = await req.json().catch(() => ({}));
  if (body.action === "me") return json({ super: isSuper });
  if (!isSuper) return json({ error: "Nur für Hauptadmins" }, 403);

  const target: string | undefined = body.user_id;
  if (["ban", "delete"].includes(body.action) && target === user.id) {
    return json({ error: "Das eigene Konto geht hier nicht" }, 400);
  }

  switch (body.action) {
    case "list": {
      const users = [];
      for (let page = 1; page <= 50; page++) {
        const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
        if (error) return json({ error: error.message }, 500);
        users.push(...data.users);
        if (data.users.length < 1000) break;
      }
      const [{ data: profiles }, { data: admins }, { data: members }] = await Promise.all([
        admin.from("profiles").select("user_id, display_name, avatar_url"),
        admin.from("tenant_admins").select("user_id, tenant_id"),
        admin.from("community_members").select("user_id, role, communities(name)").eq("status", "active"),
      ]);
      const profileBy = new Map((profiles ?? []).map((p) => [p.user_id, p]));
      return json({
        users: users.map((u) => ({
          id: u.id,
          email: u.email,
          providers: u.app_metadata?.providers ?? [u.app_metadata?.provider].filter(Boolean),
          created_at: u.created_at,
          last_sign_in_at: u.last_sign_in_at,
          banned_until: u.banned_until ?? null,
          display_name: profileBy.get(u.id)?.display_name ?? null,
          avatar_url: profileBy.get(u.id)?.avatar_url ?? null,
          super: !!u.email && superEmails.has(u.email.toLowerCase()),
          admin_tenants: (admins ?? []).filter((a) => a.user_id === u.id).map((a) => a.tenant_id),
          // deno-lint-ignore no-explicit-any
          groups: (members ?? []).filter((m) => m.user_id === u.id).map((m: any) => ({ name: m.communities?.name, role: m.role })),
        })),
      });
    }
    case "set_admin": {
      const { tenant_id, on } = body;
      const { error } = on
        ? await admin.from("tenant_admins").upsert({ tenant_id, user_id: target }, { onConflict: "tenant_id,user_id", ignoreDuplicates: true })
        : await admin.from("tenant_admins").delete().eq("tenant_id", tenant_id).eq("user_id", target);
      return error ? json({ error: error.message }, 500) : json({ ok: true });
    }
    case "set_profile": {
      const patch: Record<string, unknown> = {};
      if (typeof body.display_name === "string" && body.display_name.trim()) patch.display_name = body.display_name.trim();
      if (body.remove_avatar) {
        const { data: files } = await admin.storage.from("avatars").list(target);
        if (files?.length) await admin.storage.from("avatars").remove(files.map((f) => `${target}/${f.name}`));
        patch.avatar_url = null;
      }
      const { error } = await admin.from("profiles").update(patch).eq("user_id", target);
      return error ? json({ error: error.message }, 500) : json({ ok: true });
    }
    case "ban": {
      const { error } = await admin.auth.admin.updateUserById(target!, { ban_duration: body.on ? "876000h" : "none" });
      return error ? json({ error: error.message }, 500) : json({ ok: true });
    }
    case "delete": {
      // wie delete-account: Gruppen mit einzigem Owner archivieren, Profilbilder weg, Termine bleiben anonym
      const { data: owned } = await admin.from("community_members")
        .select("community_id").eq("user_id", target).eq("role", "owner").eq("status", "active");
      for (const row of owned ?? []) {
        const { count } = await admin.from("community_members")
          .select("*", { count: "exact", head: true })
          .eq("community_id", row.community_id).eq("role", "owner").eq("status", "active");
        if ((count ?? 0) <= 1) {
          await admin.from("communities").update({ status: "archived" }).eq("id", row.community_id).eq("status", "approved");
        }
      }
      const { data: avatars } = await admin.storage.from("avatars").list(target);
      if (avatars?.length) await admin.storage.from("avatars").remove(avatars.map((f) => `${target}/${f.name}`));
      const { error } = await admin.auth.admin.deleteUser(target!);
      return error ? json({ error: error.message }, 500) : json({ ok: true });
    }
  }
  return json({ error: "Unbekannte Aktion" }, 400);
});
