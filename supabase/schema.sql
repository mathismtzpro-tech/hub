-- =====================================================================
-- Le Hub — schéma Supabase (v6 : avatar/bannière, salon de logs, revalidation)
-- Toutes les tables commencent par hub_ : elles peuvent vivre dans le
-- MÊME projet Supabase que le dashboard Protect sans rien toucher.
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- Le script peut être relancé sans danger.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

-- Profils : un par compte Discord connecté (créé automatiquement)
create table if not exists public.hub_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  discord_id text unique,
  name text not null default 'Membre',
  avatar_url text,
  kind text not null default 'Staff / talent',      -- Staff / talent, Fondateur, Les deux
  skills text[] not null default '{}',
  bio text,
  dispo text,
  paid text default 'Bénévole',
  portfolio text,
  status text not null default 'incomplet'
    check (status in ('incomplet','en_attente','valide','refuse','suspendu')),
  refusal_reason text,
  has_link boolean generated always as
    (coalesce(bio,'') ~* '(https?://|www\.|discord\.gg|discord\.com/invite)') stored,
  verified boolean not null default false,         -- badge Talent Vérifié
  plan text not null default 'Gratuit',            -- Gratuit, Fondateur+, Fondateur Pro, Talent+, Talent Vérifié
  is_admin boolean not null default false,         -- accès au panneau admin du site
  notified_staff boolean not null default false,   -- le bot a posté la demande dans le salon de vérification
  staff_message_id text,                           -- message du bot dans le salon de vérification
  notified_user boolean not null default true,     -- false = le bot doit prévenir la personne de la décision
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Colonnes des badges (ajoutées même si la table existait déjà)
alter table public.hub_profiles add column if not exists certs text[] not null default '{}';   -- dev_bot, dev_site, graphiste, staff
alter table public.hub_profiles add column if not exists quests text[] not null default '{}';  -- quêtes Staff certifié validées
alter table public.hub_profiles add column if not exists team boolean not null default false;  -- Team Hub (synchronisé par le bot depuis le rôle staff)

-- Profils détaillés (staff / talents)
alter table public.hub_profiles add column if not exists about text;                                  -- description détaillée / ce que je propose
alter table public.hub_profiles add column if not exists skill_levels jsonb not null default '{}';    -- {"Modération":"Confirmé", ...}
alter table public.hub_profiles add column if not exists languages jsonb not null default '{}';       -- {"Anglais":"Intermédiaire", ...}
alter table public.hub_profiles add column if not exists schedule text[] not null default '{}';       -- ["lun:soir","sam:aprem", ...]
alter table public.hub_profiles add column if not exists paid_modes text[] not null default '{}';     -- {Bénévole, Rémunéré}
alter table public.hub_profiles add column if not exists rate text;                                   -- tarif indicatif
alter table public.hub_profiles add column if not exists level text;                                  -- niveau global
-- détection de liens : présentation courte ET description détaillée
alter table public.hub_profiles drop column if exists has_link;
alter table public.hub_profiles add column has_link boolean generated always as
  ((coalesce(bio,'') || ' ' || coalesce(about,'')) ~* '(https?://|www\.|discord\.gg|discord\.com/invite)') stored;

-- Avatar / bannière Discord (mis à jour par le bot et à la connexion), suivi des vérifications
alter table public.hub_profiles add column if not exists banner_url text;
alter table public.hub_profiles add column if not exists accent_color text;
alter table public.hub_profiles add column if not exists was_validated boolean not null default false;  -- déjà validé une fois = la prochaine demande est une modification
alter table public.hub_profiles add column if not exists decided_by text;                              -- qui a validé / refusé

-- Fiches serveurs : créées uniquement par la fonction claim-server
-- (qui vérifie auprès de Discord que la personne gère bien le serveur)
create table if not exists public.hub_servers (
  id bigint generated always as identity primary key,
  guild_id text unique not null,
  owner_id uuid not null references public.hub_profiles(id) on delete cascade,
  name text not null,
  icon text,
  description text,
  cat text,
  invite_url text,
  members int not null default 0,
  online int not null default 0,
  owner_verified boolean not null default false,   -- true = propriétaire, false = gestionnaire
  protect boolean not null default false,          -- mis à jour par le bot Protect
  pro boolean not null default false,              -- badge PRO (donné par le staff)
  month boolean not null default false,            -- Serveur du mois
  status text not null default 'en_attente'
    check (status in ('en_attente','valide','refuse','suspendu')),
  refusal_reason text,
  has_link boolean generated always as
    (coalesce(description,'') ~* '(https?://|www\.|discord\.gg|discord\.com/invite)') stored,
  notified_staff boolean not null default false,
  staff_message_id text,
  notified_user boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Tags et statistiques des serveurs (les stats sont remplies par Protect)
alter table public.hub_servers add column if not exists tags text[] not null default '{}' check (cardinality(tags) <= 3);
alter table public.hub_servers add column if not exists bots int;
alter table public.hub_servers add column if not exists channels int;
alter table public.hub_servers add column if not exists roles int;
alter table public.hub_servers add column if not exists boosts int;
alter table public.hub_servers add column if not exists boost_tier int;
alter table public.hub_servers add column if not exists guild_created_at timestamptz;
alter table public.hub_servers add column if not exists messages_24h int;
alter table public.hub_servers add column if not exists stats_updated_at timestamptz;

alter table public.hub_servers add column if not exists was_validated boolean not null default false;
alter table public.hub_servers add column if not exists decided_by text;

-- Historique jour par jour (courbe sur 30 jours)
create table if not exists public.hub_server_stats (
  server_id bigint not null references public.hub_servers(id) on delete cascade,
  day date not null default current_date,
  members int,
  online int,
  messages int not null default 0,
  primary key (server_id, day)
);

-- Annonces de recrutement (publiées dans le forum Discord par le bot)
create table if not exists public.hub_listings (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.hub_profiles(id) on delete cascade,
  server_id bigint not null references public.hub_servers(id) on delete cascade,
  role text not null,
  title text not null,
  description text,
  paid boolean not null default false,
  boosted boolean not null default false,
  boosted_until timestamptz,
  discord_message_id text,
  created_at timestamptz not null default now()
);

-- Candidatures
create table if not exists public.hub_applications (
  id bigint generated always as identity primary key,
  listing_id bigint not null references public.hub_listings(id) on delete cascade,
  user_id uuid not null references public.hub_profiles(id) on delete cascade,
  message text,
  status text not null default 'en attente',
  notified boolean not null default false,
  created_at timestamptz not null default now()
);

-- Contrats entre un fondateur et un membre du staff
create table if not exists public.hub_contracts (
  id bigint generated always as identity primary key,
  server_id bigint not null references public.hub_servers(id) on delete cascade,
  founder_id uuid not null references public.hub_profiles(id) on delete cascade,
  talent_id uuid not null references public.hub_profiles(id) on delete cascade,
  listing_id bigint references public.hub_listings(id) on delete set null,
  application_id bigint references public.hub_applications(id) on delete set null,
  server_name text, founder_name text, talent_name text,     -- copiés à la création
  role text not null,
  duration text not null,
  start_date date not null default current_date,
  end_date date,                                              -- vide = sans durée fixe
  trial text,
  hours text,
  schedule_text text,
  pay_mode text not null default 'benevole' check (pay_mode in ('benevole','remunere')),
  pay_amount text,
  missions text not null,
  conditions text,
  status text not null default 'propose'
    check (status in ('propose','accepte','refuse','annule','termine','rompu')),
  accepted_at timestamptz,
  ended_at timestamptz,
  ended_by uuid,
  end_reason text,
  channel_id text,                                            -- ticket Discord
  control_message_id text,
  sync_needed boolean not null default false,                 -- le bot doit mettre le ticket à jour
  created_at timestamptz not null default now(),
  check (talent_id <> founder_id)
);

-- Journal d'activité : actualités publiques + logs réservés à la Team Hub
create table if not exists public.hub_logs (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  kind text not null,                 -- serveur, profil, badge, annonce, contrat, commande, membre
  message text not null,
  public boolean not null default false,
  actor_name text,                    -- qui a fait l'action (vide = automatique / bot)
  target_type text,
  target_id text
);
create index if not exists hub_logs_created on public.hub_logs (created_at desc);

-- Avis dans les deux sens
create table if not exists public.hub_reviews (
  id bigint generated always as identity primary key,
  author_id uuid not null references public.hub_profiles(id) on delete cascade,
  target_id uuid not null references public.hub_profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (author_id, target_id)
);

-- Commandes du Studio
create table if not exists public.hub_orders (
  id bigint generated always as identity primary key,
  user_id uuid references public.hub_profiles(id) on delete set null,
  service text, theme text, colors text, size text, details text,
  status text not null default 'nouvelle',        -- nouvelle, en_cours, livree (livree = badge Client Studio)
  notified boolean not null default false,
  created_at timestamptz not null default now()
);

-- Badges personnalisés créés par le staff
create table if not exists public.hub_badges (
  id bigint generated always as identity primary key,
  label text unique not null,
  emoji text not null default '★',
  color text not null default '#5962FE' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at timestamptz not null default now()
);

-- Qui a quel badge (un serveur ou un profil)
create table if not exists public.hub_badge_links (
  badge_id bigint not null references public.hub_badges(id) on delete cascade,
  target_type text not null check (target_type in ('server','profile')),
  target_id text not null,
  primary key (badge_id, target_type, target_id)
);

insert into public.hub_badges (label, emoji, color) values
  ('Créé par le Studio', '◆', '#3ECF8E'),
  ('Partenaire', '★', '#F5B942'),
  ('Recrute activement', '⚑', '#5962FE')
on conflict (label) do nothing;

-- ---------------------------------------------------------------------
-- 2. Fonctions utiles
-- ---------------------------------------------------------------------

create or replace function public.hub_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.hub_profiles where id = auth.uid()), false);
$$;

-- "De confiance" = le bot / les fonctions (clé service_role), l'éditeur SQL, ou un admin du site
create or replace function public.hub_is_trusted() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(auth.role(), 'service_role') = 'service_role' or public.hub_is_admin();
$$;

-- Création automatique du profil à la première connexion Discord
create or replace function public.hub_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.hub_profiles (id, discord_id, name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data->>'provider_id',
    coalesce(new.raw_user_meta_data->'custom_claims'->>'global_name',
             new.raw_user_meta_data->>'full_name',
             new.raw_user_meta_data->>'name', 'Membre'),
    new.raw_user_meta_data->>'avatar_url')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists hub_on_auth_user_created on auth.users;
create trigger hub_on_auth_user_created
  after insert on auth.users
  for each row execute function public.hub_handle_new_user();

-- Comptes qui existaient déjà (ex. utilisateurs du dashboard Protect)
insert into public.hub_profiles (id, discord_id, name, avatar_url)
select u.id,
       u.raw_user_meta_data->>'provider_id',
       coalesce(u.raw_user_meta_data->'custom_claims'->>'global_name',
                u.raw_user_meta_data->>'full_name',
                u.raw_user_meta_data->>'name', 'Membre'),
       u.raw_user_meta_data->>'avatar_url'
from auth.users u
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 3. Protections : un membre ne peut pas se donner un badge, un plan,
--    ni valider lui-même sa fiche. Toute modification du contenu
--    renvoie la fiche ou le profil en vérification.
-- ---------------------------------------------------------------------

create or replace function public.hub_guard_profiles() returns trigger
language plpgsql set search_path = public as $$
begin
  if public.hub_is_trusted() then
    -- un admin qui modifie le contenu de SON propre profil passe aussi par la vérification
    -- (comme tout le monde : pratique pour tester le salon de vérification)
    if auth.uid() = new.id and new.status = old.status and
       (new.name, new.kind, new.skills, new.bio, new.dispo, new.paid, new.portfolio,
        new.about, new.skill_levels, new.languages, new.schedule, new.paid_modes, new.rate, new.level)
       is distinct from
       (old.name, old.kind, old.skills, old.bio, old.dispo, old.paid, old.portfolio,
        old.about, old.skill_levels, old.languages, old.schedule, old.paid_modes, old.rate, old.level) then
      new.status := 'en_attente'; new.notified_staff := false; new.refusal_reason := null;
    end if;
    -- une décision du staff (site ou Discord) : le bot prévient la personne et range la demande dans les logs
    if new.status is distinct from old.status and new.status in ('valide','refuse','suspendu') then
      new.notified_user := false;
    end if;
    if new.status = 'valide' then new.was_validated := true; end if;
    new.updated_at := now(); return new;
  end if;
  new.id := old.id; new.discord_id := old.discord_id; new.avatar_url := old.avatar_url;
  new.verified := old.verified; new.plan := old.plan; new.is_admin := old.is_admin;
  new.status := old.status; new.refusal_reason := old.refusal_reason;
  new.notified_staff := old.notified_staff; new.staff_message_id := old.staff_message_id; new.notified_user := old.notified_user;
  new.certs := old.certs; new.quests := old.quests; new.team := old.team;
  new.banner_url := old.banner_url; new.accent_color := old.accent_color;
  new.was_validated := old.was_validated; new.decided_by := old.decided_by;
  if (new.name, new.kind, new.skills, new.bio, new.dispo, new.paid, new.portfolio,
      new.about, new.skill_levels, new.languages, new.schedule, new.paid_modes, new.rate, new.level)
     is distinct from
     (old.name, old.kind, old.skills, old.bio, old.dispo, old.paid, old.portfolio,
      old.about, old.skill_levels, old.languages, old.schedule, old.paid_modes, old.rate, old.level) then
    new.status := 'en_attente'; new.notified_staff := false; new.refusal_reason := null;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists hub_guard_profiles on public.hub_profiles;
create trigger hub_guard_profiles before update on public.hub_profiles
  for each row execute function public.hub_guard_profiles();

create or replace function public.hub_guard_servers() returns trigger
language plpgsql set search_path = public as $$
begin
  if public.hub_is_trusted() then
    -- une décision du staff (site ou Discord) : le bot prévient la personne et range la demande dans les logs
    if new.status is distinct from old.status and new.status in ('valide','refuse','suspendu') then
      new.notified_user := false;
    end if;
    if new.status = 'valide' then new.was_validated := true; end if;
    new.updated_at := now(); return new;
  end if;
  new.guild_id := old.guild_id; new.owner_id := old.owner_id; new.name := old.name; new.icon := old.icon;
  new.members := old.members; new.online := old.online; new.owner_verified := old.owner_verified;
  new.protect := old.protect; new.pro := old.pro; new.month := old.month;
  new.status := old.status; new.refusal_reason := old.refusal_reason;
  new.notified_staff := old.notified_staff; new.staff_message_id := old.staff_message_id; new.notified_user := old.notified_user;
  new.was_validated := old.was_validated; new.decided_by := old.decided_by;
  new.bots := old.bots; new.channels := old.channels; new.roles := old.roles; new.boosts := old.boosts;
  new.boost_tier := old.boost_tier; new.guild_created_at := old.guild_created_at;
  new.messages_24h := old.messages_24h; new.stats_updated_at := old.stats_updated_at;
  if (new.description, new.cat, new.invite_url, new.tags)
     is distinct from (old.description, old.cat, old.invite_url, old.tags) then
    new.status := 'en_attente'; new.notified_staff := false; new.refusal_reason := null;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists hub_guard_servers on public.hub_servers;
create trigger hub_guard_servers before update on public.hub_servers
  for each row execute function public.hub_guard_servers();

create or replace function public.hub_guard_listings() returns trigger
language plpgsql set search_path = public as $$
begin
  if public.hub_is_trusted() then return new; end if;
  if tg_op = 'INSERT' then
    new.boosted := false; new.boosted_until := null; new.discord_message_id := null;
  else
    new.owner_id := old.owner_id; new.server_id := old.server_id;
    new.boosted := old.boosted; new.boosted_until := old.boosted_until;
    new.discord_message_id := old.discord_message_id;
  end if;
  return new;
end $$;
drop trigger if exists hub_guard_listings on public.hub_listings;
create trigger hub_guard_listings before insert or update on public.hub_listings
  for each row execute function public.hub_guard_listings();

-- Team Hub (staff du serveur) : voit tous les contrats
create or replace function public.hub_is_team() returns boolean
language sql stable security definer set search_path = public as $$
  select public.hub_is_admin() or coalesce((select team from public.hub_profiles where id = auth.uid()), false);
$$;

-- Contrats : un membre ne peut créer qu'une proposition ; les noms sont copiés ;
-- tout changement de statut prévient le bot (sync_needed) pour mettre le ticket à jour
create or replace function public.hub_contracts_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if not public.hub_is_trusted() then
      new.status := 'propose'; new.accepted_at := null; new.ended_at := null; new.ended_by := null;
      new.end_reason := null; new.channel_id := null; new.control_message_id := null; new.sync_needed := false;
    end if;
    select name into new.server_name from public.hub_servers where id = new.server_id;
    select name into new.founder_name from public.hub_profiles where id = new.founder_id;
    select name into new.talent_name from public.hub_profiles where id = new.talent_id;
  elsif new.status is distinct from old.status then
    new.sync_needed := true;
  end if;
  return new;
end $$;
drop trigger if exists hub_contracts_before on public.hub_contracts;
create trigger hub_contracts_before before insert or update on public.hub_contracts
  for each row execute function public.hub_contracts_before();

-- Les seules actions possibles sur un contrat depuis le site
create or replace function public.hub_contract_action(p_id bigint, p_action text, p_reason text default null)
returns text language plpgsql security definer set search_path = public as $$
declare c public.hub_contracts; uid uuid := auth.uid();
begin
  select * into c from public.hub_contracts where id = p_id for update;
  if not found then raise exception 'Contrat introuvable'; end if;
  if p_action = 'accepter' and uid = c.talent_id and c.status = 'propose' then
    update public.hub_contracts set status = 'accepte', accepted_at = now() where id = p_id;
  elsif p_action = 'refuser' and uid = c.talent_id and c.status = 'propose' then
    update public.hub_contracts set status = 'refuse', ended_at = now(), ended_by = uid, end_reason = p_reason where id = p_id;
  elsif p_action = 'annuler' and uid = c.founder_id and c.status = 'propose' then
    update public.hub_contracts set status = 'annule', ended_at = now(), ended_by = uid, end_reason = p_reason where id = p_id;
  elsif p_action = 'terminer' and uid in (c.founder_id, c.talent_id) and c.status = 'accepte' then
    update public.hub_contracts set status = 'termine', ended_at = now(), ended_by = uid, end_reason = p_reason where id = p_id;
  elsif p_action = 'rompre' and public.hub_is_team() and c.status in ('propose','accepte') then
    update public.hub_contracts set status = 'rompu', ended_at = now(), ended_by = uid, end_reason = p_reason where id = p_id;
  else
    raise exception 'Action impossible sur ce contrat';
  end if;
  return 'ok';
end $$;
revoke all on function public.hub_contract_action(bigint, text, text) from public;
grant execute on function public.hub_contract_action(bigint, text, text) to authenticated;


-- ---------------------------------------------------------------------
-- Journal d'activité : écrit automatiquement par la base, personne ne peut tricher
-- ---------------------------------------------------------------------
create or replace function public.hub_log(p_kind text, p_msg text, p_public boolean, p_type text default null, p_id text default null)
returns void language plpgsql security definer set search_path = public as $$
declare who text;
begin
  select name into who from public.hub_profiles where id = auth.uid();
  insert into public.hub_logs(kind, message, public, actor_name, target_type, target_id)
  values (p_kind, p_msg, p_public, who, p_type, p_id);
  delete from public.hub_logs where created_at < now() - interval '120 days';
end $$;
revoke all on function public.hub_log(text, text, boolean, text, text) from public;

create or replace function public.hub_log_servers() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.hub_log('serveur', 'Nouvelle fiche serveur à vérifier : ' || new.name, false, 'server', new.id::text);
  elsif new.status is distinct from old.status then
    if new.status = 'valide' then
      perform public.hub_log('serveur', 'Nouveau serveur vérifié : ' || new.name, true, 'server', new.id::text);
    elsif new.status = 'en_attente' then
      perform public.hub_log('serveur', 'Fiche modifiée, à revérifier : ' || new.name, false, 'server', new.id::text);
    else
      perform public.hub_log('serveur', 'Fiche ' || new.name || ' : ' || new.status || coalesce(' (' || new.refusal_reason || ')', ''), false, 'server', new.id::text);
    end if;
  end if;
  if tg_op = 'UPDATE' and new.month and not old.month then
    perform public.hub_log('badge', new.name || ' est le Serveur du mois', true, 'server', new.id::text);
  end if;
  return null;
end $$;
drop trigger if exists hub_log_servers on public.hub_servers;
create trigger hub_log_servers after insert or update on public.hub_servers
  for each row execute function public.hub_log_servers();

create or replace function public.hub_log_profiles() returns trigger
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if tg_op = 'INSERT' then
    perform public.hub_log('membre', 'Nouveau membre inscrit : ' || new.name, false, 'profile', new.id::text);
    return null;
  end if;
  if new.status is distinct from old.status then
    if new.status = 'valide' then
      perform public.hub_log('profil', 'Nouveau profil vérifié : ' || new.name, true, 'profile', new.id::text);
    elsif new.status = 'en_attente' then
      perform public.hub_log('profil', 'Profil à vérifier : ' || new.name, false, 'profile', new.id::text);
    else
      perform public.hub_log('profil', 'Profil ' || new.name || ' : ' || new.status || coalesce(' (' || new.refusal_reason || ')', ''), false, 'profile', new.id::text);
    end if;
  end if;
  foreach c in array coalesce(new.certs, '{}') loop
    if not (c = any(coalesce(old.certs, '{}'))) then
      perform public.hub_log('badge', new.name || ' est maintenant ' ||
        case c when 'staff' then 'Staff certifié' when 'dev_bot' then 'Développeur bot certifié'
               when 'dev_site' then 'Développeur site certifié' when 'graphiste' then 'Graphiste certifié' else c end,
        true, 'profile', new.id::text);
    end if;
  end loop;
  if new.plan is distinct from old.plan then
    perform public.hub_log('badge', 'Formule de ' || new.name || ' : ' || old.plan || ' → ' || new.plan, false, 'profile', new.id::text);
  end if;
  if new.verified is distinct from old.verified then
    perform public.hub_log('badge', 'Expériences vérifiées ' || case when new.verified then 'données à ' else 'retirées à ' end || new.name, false, 'profile', new.id::text);
  end if;
  if new.is_admin is distinct from old.is_admin then
    perform public.hub_log('membre', new.name || case when new.is_admin then ' devient admin du site' else ' n''est plus admin du site' end, false, 'profile', new.id::text);
  end if;
  return null;
end $$;
drop trigger if exists hub_log_profiles on public.hub_profiles;
create trigger hub_log_profiles after insert or update on public.hub_profiles
  for each row execute function public.hub_log_profiles();

create or replace function public.hub_log_badge_links() returns trigger
language plpgsql security definer set search_path = public as $$
declare b text; t text; r record;
begin
  r := coalesce(new, old);
  select label into b from public.hub_badges where id = r.badge_id;
  if r.target_type = 'server' then select name into t from public.hub_servers where id::text = r.target_id;
  else select name into t from public.hub_profiles where id::text = r.target_id; end if;
  if tg_op = 'INSERT' then
    perform public.hub_log('badge', coalesce(t, '?') || ' reçoit le badge « ' || coalesce(b, '?') || ' »', true, r.target_type, r.target_id);
  else
    perform public.hub_log('badge', 'Badge « ' || coalesce(b, '?') || ' » retiré à ' || coalesce(t, '?'), false, r.target_type, r.target_id);
  end if;
  return null;
end $$;
drop trigger if exists hub_log_badge_links on public.hub_badge_links;
create trigger hub_log_badge_links after insert or delete on public.hub_badge_links
  for each row execute function public.hub_log_badge_links();

create or replace function public.hub_log_listings() returns trigger
language plpgsql security definer set search_path = public as $$
declare srv text;
begin
  select name into srv from public.hub_servers where id = new.server_id;
  perform public.hub_log('annonce', coalesce(srv, 'Un serveur') || ' recrute : ' || new.role, true, 'listing', new.id::text);
  return null;
end $$;
drop trigger if exists hub_log_listings on public.hub_listings;
create trigger hub_log_listings after insert on public.hub_listings
  for each row execute function public.hub_log_listings();

create or replace function public.hub_log_contracts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.hub_log('contrat', 'Contrat n° ' || new.id || ' proposé : ' || new.founder_name || ' → ' || new.talent_name || ' (' || new.role || ', ' || new.server_name || ')', false, 'contract', new.id::text);
  elsif new.status is distinct from old.status then
    if new.status = 'accepte' then
      perform public.hub_log('contrat', 'Nouveau contrat signé sur ' || new.server_name || ' (' || new.role || ')', true, 'contract', new.id::text);
    end if;
    perform public.hub_log('contrat', 'Contrat n° ' || new.id || ' : ' || new.status || coalesce(' (' || new.end_reason || ')', ''), false, 'contract', new.id::text);
  end if;
  return null;
end $$;
drop trigger if exists hub_log_contracts on public.hub_contracts;
create trigger hub_log_contracts after insert or update on public.hub_contracts
  for each row execute function public.hub_log_contracts();

create or replace function public.hub_log_orders() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.hub_log('commande', 'Nouvelle commande Studio : ' || coalesce(new.service, '?'), false, 'order', new.id::text);
  elsif new.status is distinct from old.status and new.status = 'livree' then
    perform public.hub_log('commande', 'Commande Studio livrée (' || coalesce(new.service, '?') || ')', true, 'order', new.id::text);
  end if;
  return null;
end $$;
drop trigger if exists hub_log_orders on public.hub_orders;
create trigger hub_log_orders after insert or update on public.hub_orders
  for each row execute function public.hub_log_orders();

-- ---------------------------------------------------------------------
-- 4. Vue publique des talents (seulement les profils validés)
-- ---------------------------------------------------------------------
drop view if exists public.hub_talents;
create view public.hub_talents as
select p.id, p.name, p.avatar_url, p.skills, p.bio as exp, p.paid, p.dispo,
       p.verified, p.portfolio, p.created_at,
       p.about, p.skill_levels, p.languages, p.schedule, p.paid_modes, p.rate, p.level,
       p.banner_url, p.accent_color,
       coalesce(round(avg(r.rating)::numeric, 1), 0) as rating,
       count(r.id) as reviews
from public.hub_profiles p
left join public.hub_reviews r on r.target_id = p.id
where p.status = 'valide' and p.kind <> 'Fondateur'
group by p.id;
grant select on public.hub_talents to anon, authenticated;

-- Badges de chaque membre (lue par le site et par le bot)
--   fondateur_certifie : propriétaire d'un serveur dont la fiche est validée
--   client_studio      : au moins une commande Studio livrée
create or replace view public.hub_profile_badges as
select p.id, p.discord_id, p.plan, p.verified, p.certs, p.quests, p.team,
       exists (select 1 from public.hub_servers s
               where s.owner_id = p.id and s.status = 'valide' and s.owner_verified) as fondateur_certifie,
       exists (select 1 from public.hub_orders o
               where o.user_id = p.id and o.status = 'livree') as client_studio
from public.hub_profiles p;
grant select on public.hub_profile_badges to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Sécurité (RLS)
-- ---------------------------------------------------------------------
alter table public.hub_profiles     enable row level security;
alter table public.hub_servers      enable row level security;
alter table public.hub_listings     enable row level security;
alter table public.hub_applications enable row level security;
alter table public.hub_reviews      enable row level security;
alter table public.hub_orders       enable row level security;
alter table public.hub_badges       enable row level security;
alter table public.hub_badge_links  enable row level security;
alter table public.hub_server_stats enable row level security;
alter table public.hub_contracts    enable row level security;
alter table public.hub_logs         enable row level security;

do $$ declare p record; begin
  for p in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename like 'hub\_%' loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- Profils
create policy "profils visibles" on public.hub_profiles for select
  using (status = 'valide' or id = auth.uid() or public.hub_is_admin());
create policy "modifier son profil" on public.hub_profiles for update
  using (id = auth.uid() or public.hub_is_admin());
create policy "supprimer son profil" on public.hub_profiles for delete
  using (id = auth.uid() or public.hub_is_admin());

-- Serveurs (pas d'insert ici : c'est la fonction claim-server qui crée les fiches)
create policy "serveurs visibles" on public.hub_servers for select
  using (status = 'valide' or owner_id = auth.uid() or public.hub_is_admin());
create policy "modifier sa fiche" on public.hub_servers for update
  using (owner_id = auth.uid() or public.hub_is_admin());
create policy "supprimer sa fiche" on public.hub_servers for delete
  using (owner_id = auth.uid() or public.hub_is_admin());

-- Annonces : il faut une fiche serveur validée pour publier
create policy "annonces visibles" on public.hub_listings for select using (true);
create policy "publier une annonce" on public.hub_listings for insert
  with check (owner_id = auth.uid() and exists (
    select 1 from public.hub_servers s
    where s.id = server_id and s.owner_id = auth.uid() and s.status = 'valide'));
create policy "modifier son annonce" on public.hub_listings for update
  using (owner_id = auth.uid() or public.hub_is_admin());
create policy "supprimer son annonce" on public.hub_listings for delete
  using (owner_id = auth.uid() or public.hub_is_admin());

-- Candidatures
create policy "postuler" on public.hub_applications for insert
  with check (user_id = auth.uid() and exists (
    select 1 from public.hub_profiles p where p.id = auth.uid() and p.status = 'valide'));
create policy "voir les candidatures" on public.hub_applications for select
  using (user_id = auth.uid() or public.hub_is_admin() or exists (
    select 1 from public.hub_listings l where l.id = listing_id and l.owner_id = auth.uid()));

-- Statistiques des serveurs (écrites par le bot uniquement)
create policy "stats visibles" on public.hub_server_stats for select using (true);

-- Contrats : visibles par les deux personnes et par la Team Hub ;
-- les changements de statut passent par hub_contract_action()
create policy "voir ses contrats" on public.hub_contracts for select
  using (founder_id = auth.uid() or talent_id = auth.uid() or public.hub_is_team());
create policy "proposer un contrat" on public.hub_contracts for insert
  with check (
    founder_id = auth.uid()
    and exists (select 1 from public.hub_servers s
                where s.id = server_id and s.owner_id = auth.uid() and s.status = 'valide')
    and exists (select 1 from public.hub_profiles p where p.id = talent_id and p.status = 'valide')
    and (select count(*) from public.hub_contracts x
         where x.founder_id = auth.uid() and x.status = 'propose') < 5);

-- Journal : actualités publiques pour tous, tout le journal pour la Team Hub
create policy "journal" on public.hub_logs for select using (public or public.hub_is_team());

-- Avis
create policy "avis visibles" on public.hub_reviews for select using (true);
create policy "laisser un avis" on public.hub_reviews for insert
  with check (author_id = auth.uid() and author_id <> target_id);

-- Commandes du Studio
create policy "commander" on public.hub_orders for insert with check (user_id = auth.uid());
create policy "voir ses commandes" on public.hub_orders for select
  using (user_id = auth.uid() or public.hub_is_admin());
create policy "gérer les commandes" on public.hub_orders for update using (public.hub_is_admin());

-- Badges : lecture pour tous, gestion réservée aux admins
create policy "badges visibles" on public.hub_badges for select using (true);
create policy "gérer les badges" on public.hub_badges for all
  using (public.hub_is_admin()) with check (public.hub_is_admin());
create policy "attributions visibles" on public.hub_badge_links for select using (true);
create policy "attribuer les badges" on public.hub_badge_links for all
  using (public.hub_is_admin()) with check (public.hub_is_admin());

-- ---------------------------------------------------------------------
-- 6. Te donner l'accès admin (à lancer APRÈS ta première connexion au site)
--    Remplace par ton identifiant Discord (Discord > Paramètres > Avancés >
--    Mode développeur, puis clic droit sur ton pseudo > Copier l'identifiant)
-- ---------------------------------------------------------------------
-- update public.hub_profiles set is_admin = true, status = 'valide' where discord_id = 'TON_ID_DISCORD';

-- Fiches et profils déjà validés avant cette version : la prochaine demande sera une « modification »
update public.hub_profiles set was_validated = true where status = 'valide' and not was_validated;
update public.hub_servers  set was_validated = true where status = 'valide' and not was_validated;

-- ---------------------------------------------------------------------
-- 7. Prévient l'API de Supabase que les tables ont changé (évite l'erreur
--    "Could not find the ... column ... in the schema cache")
-- ---------------------------------------------------------------------
notify pgrst, 'reload schema';
