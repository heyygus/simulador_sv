-- =============================================================
--  SimLab · Migración 4: Progreso por módulo (student_progress)
--  Corre en el SQL Editor de Supabase DESPUÉS de las migraciones 1-3
-- =============================================================
-- Crea la tabla student_progress para guardar el avance por escenario
-- de forma permanente e independiente de la sesión del navegador.

-- =============================================================
-- 1. Tabla student_progress
-- =============================================================
CREATE TABLE IF NOT EXISTS public.student_progress (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    scenario_id     INT         NOT NULL CHECK (scenario_id BETWEEN 1 AND 5),
    scenario_name   TEXT        NOT NULL,
    completed       BOOLEAN     NOT NULL DEFAULT FALSE,
    wrong_attempts  INT         NOT NULL DEFAULT 0,
    score           NUMERIC(5,2),
    completed_at    TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (profile_id, scenario_id)
);

ALTER TABLE public.student_progress ENABLE ROW LEVEL SECURITY;

-- =============================================================
-- 2. RLS: estudiante gestiona su propio progreso
-- =============================================================
DROP POLICY IF EXISTS "student_progress: own read"   ON public.student_progress;
DROP POLICY IF EXISTS "student_progress: own insert" ON public.student_progress;
DROP POLICY IF EXISTS "student_progress: own update" ON public.student_progress;

CREATE POLICY "student_progress: own read"
    ON public.student_progress FOR SELECT TO authenticated
    USING (profile_id = auth.uid());

CREATE POLICY "student_progress: own insert"
    ON public.student_progress FOR INSERT TO authenticated
    WITH CHECK (profile_id = auth.uid());

CREATE POLICY "student_progress: own update"
    ON public.student_progress FOR UPDATE TO authenticated
    USING (profile_id = auth.uid());

-- =============================================================
-- 3. RLS: admin ve todo
-- =============================================================
DROP POLICY IF EXISTS "student_progress: admin sees all" ON public.student_progress;

CREATE POLICY "student_progress: admin sees all"
    ON public.student_progress FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- =============================================================
-- 4. Índice para consultas frecuentes
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_student_progress_profile_id
    ON public.student_progress(profile_id);

-- =============================================================
-- Fin de migration_progress.sql
-- =============================================================
