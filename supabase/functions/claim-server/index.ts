// =====================================================================
// Le Hub — fonction "claim-server"
// Vérifie auprès de Discord que la personne gère vraiment un serveur
// avant de créer sa fiche. Le site ne peut pas tricher : c'est cette
// fonction (côté Supabase) qui écrit dans hub_servers.
//
// mode "list"    : renvoie les serveurs que la personne peut gérer
// mode "claim"   : crée la fiche d'un serveur (en attente de vérification)
// mode "refresh" : appelé à chaque connexion, met à jour les chiffres et
//                  suspend les fiches dont la personne n'a plus les droits
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
// Toujours 200 : le site lit le champ "error" s'il y en a un
const reply = (body: unknown) =>
  new Response(JSON.stringify(body), { headers: { ...cors, "Content-Type": "application/json" } });

const MANAGE_GUILD = 0x20n;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. Qui appelle ? (session Supabase du site)
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return reply({ error: "Tu dois être connecté." });

    const { mode = "list", guild_id, provider_token } = await req.json();
    if (!provider_token) return reply({ error: "reconnect" });
    const dh = { Authorization: `Bearer ${provider_token}` };

    // 2. Le jeton Discord appartient bien à ce compte ?
    const meRes = await fetch("https://discord.com/api/v10/users/@me", { headers: dh });
    if (!meRes.ok) return reply({ error: "reconnect" });
    const me = await meRes.json();
    const discordId = user.user_metadata?.provider_id ??
      user.identities?.find((i) => i.provider === "discord")?.id;
    if (me.id !== discordId) return reply({ error: "Ce compte Discord ne correspond pas à ta session." });

    // 3. Ses serveurs, avec les chiffres approximatifs
    const gRes = await fetch("https://discord.com/api/v10/users/@me/guilds?with_counts=true", { headers: dh });
    if (!gRes.ok) return reply({ error: "Discord ne répond pas, réessaie dans une minute." });
    // deno-lint-ignore no-explicit-any
    const guilds = (await gRes.json()).filter((g: any) =>
      g.owner || (BigInt(g.permissions) & MANAGE_GUILD) === MANAGE_GUILD
    );
    // deno-lint-ignore no-explicit-any
    const ids = guilds.map((g: any) => g.id);
    const { data: existing } = ids.length
      ? await admin.from("hub_servers").select("id, guild_id, owner_id, status").in("guild_id", ids)
      : { data: [] };

    // deno-lint-ignore no-explicit-any
    const counts = (g: any) => ({
      members: g.approximate_member_count ?? 0,
      online: g.approximate_presence_count ?? 0,
    });

    if (mode === "list") {
      // deno-lint-ignore no-explicit-any
      return reply(guilds.map((g: any) => {
        const e = existing?.find((x) => x.guild_id === g.id);
        return { id: g.id, name: g.name, icon: g.icon, owner: g.owner, ...counts(g), claimed: !!e, mine: e?.owner_id === user.id };
      }));
    }

    if (mode === "claim") {
      // deno-lint-ignore no-explicit-any
      const g = guilds.find((x: any) => x.id === String(guild_id));
      if (!g) return reply({ error: "Tu ne gères pas ce serveur." });
      const e = existing?.find((x) => x.guild_id === g.id);
      // Un gestionnaire ne peut pas prendre la fiche d'un autre ; le vrai propriétaire, si.
      if (e && e.owner_id !== user.id && !g.owner) return reply({ error: "Ce serveur a déjà une fiche." });
      const { error } = await admin.from("hub_servers").upsert({
        guild_id: g.id, owner_id: user.id, name: g.name, icon: g.icon,
        owner_verified: g.owner, ...counts(g),
        status: "en_attente", notified_staff: false, refusal_reason: null,
      }, { onConflict: "guild_id" });
      return reply(error ? { error: error.message } : { ok: true });
    }

    if (mode === "refresh") {
      const { data: mine } = await admin.from("hub_servers").select("id, guild_id, status").eq("owner_id", user.id);
      for (const s of mine ?? []) {
        // deno-lint-ignore no-explicit-any
        const g = guilds.find((x: any) => x.id === s.guild_id);
        if (!g) {
          await admin.from("hub_servers").update({
            status: "suspendu",
            refusal_reason: "Tu n'as plus les droits de gestion sur ce serveur.",
          }).eq("id", s.id);
        } else {
          await admin.from("hub_servers").update({
            name: g.name, icon: g.icon, owner_verified: g.owner, ...counts(g),
          }).eq("id", s.id);
        }
      }
      return reply({ ok: true });
    }

    return reply({ error: "Mode inconnu." });
  } catch (e) {
    return reply({ error: String(e) });
  }
});
