-- =============================================================
--  SimLab · Migración 3: Políticas de admin full-access
--  Corre en el SQL Editor de Supabase
-- =============================================================
-- El admin ve todos los datos usando auth.jwt() para evitar
-- recursión en las RLS de la propia tabla profiles.

-- profiles
DROP POLICY IF EXISTS "profiles: admin sees all" ON public.profiles;
CREATE POLICY "profiles: admin sees all"
    ON public.profiles FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- sessions
DROP POLICY IF EXISTS "sessions: admin sees all" ON public.sessions;
CREATE POLICY "sessions: admin sees all"
    ON public.sessions FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- scenario_results
DROP POLICY IF EXISTS "scenario_results: admin sees all" ON public.scenario_results;
CREATE POLICY "scenario_results: admin sees all"
    ON public.scenario_results FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- students (tabla legacy de códigos de acceso)
DROP POLICY IF EXISTS "students: admin sees all" ON public.students;
CREATE POLICY "students: admin sees all"
    ON public.students FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- courses
DROP POLICY IF EXISTS "courses: admin sees all" ON public.courses;
CREATE POLICY "courses: admin sees all"
    ON public.courses FOR SELECT TO authenticated
    USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
