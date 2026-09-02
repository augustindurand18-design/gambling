-- 0008 — Preuves soumises et resultat de verification

create table public.proofs (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals(id) on delete cascade,
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  -- Fichier
  storage_path text,                     -- mis a NULL par purge-proofs apres retention
  image_sha256 text not null check (image_sha256 ~ '^[0-9a-f]{64}$'),
  image_bytes int,

  -- Horodatage : captured_at vient de l'appareil, donc NON fiable.
  -- server_received_at fait foi.
  captured_at timestamptz,
  server_received_at timestamptz not null default now(),

  -- Localisation declaree par l'appareil (non fiable par defaut)
  device_lat double precision,
  device_lng double precision,
  location_trusted boolean not null default false,

  exif jsonb,

  -- Pre-filtre Apple Vision execute sur l'appareil (gratuit, non autoritaire)
  -- { screenshotScore, screenDetected, objectHints[], passed }
  ondevice_precheck jsonb,

  -- Controles anti-triche serveur
  -- { captureDelaySec, insideWindow, exifConsistent, hashDuplicate, submittedBeforeWindow }
  anticheat jsonb,

  -- Verdict IA
  ai_verdict verdict,
  ai_confidence numeric(4,3) check (ai_confidence between 0 and 1),
  ai_reason text,
  ai_spoof_suspected boolean,
  ai_model text,
  ai_raw jsonb,
  ai_completed_at timestamptz,

  -- Verdict final (IA ou reviewer humain)
  final_verdict verdict,
  decided_by text,                       -- 'ai' | 'reviewer:<uuid>'
  decided_at timestamptz,

  created_at timestamptz not null default now()
);

create index proofs_goal_idx on public.proofs (goal_id);
create index proofs_user_idx on public.proofs (user_id, created_at desc);
-- Detection de reutilisation d'une meme image, tous utilisateurs confondus
create index proofs_sha_idx on public.proofs (image_sha256);
