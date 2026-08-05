-- =============================================================
--  SimLab · Migración 5: intentos por escenario (passed + stages_correct)
--  Corre DESPUÉS de migration_progress.sql
-- =============================================================
-- Agrega dos columnas a scenario_results para rastrear si el
-- estudiante aprobó cada intento y cuántas etapas respondió bien.

ALTER TABLE public.scenario_results
  ADD COLUMN IF NOT EXISTS passed        BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS stages_correct INT     NOT NULL DEFAULT 0;

-- Los registros anteriores tienen completed=TRUE y representan
-- intentos exitosos, así que se retroalimentan como aprobados.
UPDATE public.scenario_results
   SET passed         = TRUE,
       stages_correct = COALESCE(stages_completed, stages_total, 3)
 WHERE completed = TRUE
   AND passed    = FALSE;

-- =============================================================
-- RLS: estudiante puede leer sus propios scenario_results
--      (a través de sessions.profile_id)
-- =============================================================
DROP POLICY IF EXISTS "scenario_results: student sees own" ON public.scenario_results;
CREATE POLICY "scenario_results: student sees own"
    ON public.scenario_results FOR SELECT TO authenticated
    USING (
        session_id IN (
            SELECT id FROM public.sessions WHERE profile_id = auth.uid()
        )
    );

-- =============================================================
-- Fin de migration_scenario_attempts.sql
-- =============================================================
