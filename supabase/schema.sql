-- =============================================================
--  SimLab · Electrical Lab Simulator
--  Supabase PostgreSQL Schema
--  Universidad venezolana · Servicio Comunitario 2026-1
-- =============================================================


-- =============================================================
-- 1. PROFILES  (extends auth.users — professors / admins only)
-- =============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id          UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       TEXT        NOT NULL,
    name        TEXT        NOT NULL,
    role        TEXT        NOT NULL DEFAULT 'professor'
                                CHECK (role IN ('admin', 'professor')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;


-- =============================================================
-- 2. COURSES
-- =============================================================
CREATE TABLE IF NOT EXISTS public.courses (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    professor_id  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    name          TEXT        NOT NULL,
    section       TEXT,
    semester      TEXT,
    subject_code  TEXT        NOT NULL DEFAULT '41151',
    active        BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;


-- =============================================================
-- 3. ACCESS-CODE GENERATOR
--    Generates a unique 6-character uppercase alphanumeric code
--    using an unambiguous character set (no 0/O, 1/I confusion).
-- =============================================================
CREATE OR REPLACE FUNCTION public.generate_access_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    chars    TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    code     TEXT := '';
    i        INT;
    attempts INT  := 0;
BEGIN
    LOOP
        code := '';
        FOR i IN 1..6 LOOP
            code := code || substr(chars, floor(random() * length(chars) + 1)::INT, 1);
        END LOOP;

        -- Ensure global uniqueness across all students
        IF NOT EXISTS (SELECT 1 FROM public.students WHERE access_code = code) THEN
            RETURN code;
        END IF;

        attempts := attempts + 1;
        IF attempts > 200 THEN
            RAISE EXCEPTION 'generate_access_code: could not produce unique code after 200 tries';
        END IF;
    END LOOP;
END;
$$;


-- =============================================================
-- 4. STUDENTS
-- =============================================================
CREATE TABLE IF NOT EXISTS public.students (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id    UUID        NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    full_name    TEXT        NOT NULL,
    cedula       TEXT        NOT NULL,
    email        TEXT,
    access_code  TEXT        UNIQUE,          -- auto-populated by trigger if omitted
    active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;


-- Trigger function: fills access_code before INSERT when caller leaves it NULL
CREATE OR REPLACE FUNCTION public.set_student_access_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.access_code IS NULL OR trim(NEW.access_code) = '' THEN
        NEW.access_code := public.generate_access_code();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_set_student_access_code
    BEFORE INSERT ON public.students
    FOR EACH ROW
    EXECUTE FUNCTION public.set_student_access_code();


-- =============================================================
-- 5. SESSIONS
-- =============================================================
CREATE TABLE IF NOT EXISTS public.sessions (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id           UUID        REFERENCES public.students(id) ON DELETE SET NULL,
    course_id            UUID        REFERENCES public.courses(id)  ON DELETE SET NULL,
    started_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at         TIMESTAMPTZ,
    status               TEXT        NOT NULL DEFAULT 'in_progress'
                                         CHECK (status IN ('in_progress', 'completed', 'abandoned')),
    total_score          NUMERIC(5,2) DEFAULT 0
                                         CHECK (total_score >= 0 AND total_score <= 100),
    scenarios_completed  INT         DEFAULT 0
                                         CHECK (scenarios_completed >= 0 AND scenarios_completed <= 5),
    total_wrong_attempts INT         DEFAULT 0,
    user_agent           TEXT
);

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;


-- =============================================================
-- 6. SCENARIO_RESULTS
-- =============================================================
CREATE TABLE IF NOT EXISTS public.scenario_results (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID        NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
    scenario_id         INT         NOT NULL CHECK (scenario_id BETWEEN 1 AND 5),
    scenario_name       TEXT        NOT NULL,
    completed           BOOLEAN     NOT NULL DEFAULT FALSE,
    wrong_attempts      INT         NOT NULL DEFAULT 0,
    stages_completed    INT         NOT NULL DEFAULT 0,
    stages_total        INT         NOT NULL DEFAULT 3,
    completed_at        TIMESTAMPTZ,
    time_spent_seconds  INT         DEFAULT 0
);

ALTER TABLE public.scenario_results ENABLE ROW LEVEL SECURITY;


-- =============================================================
-- 7. INDEXES  (frequently queried columns)
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_courses_professor_id         ON public.courses(professor_id);
CREATE INDEX IF NOT EXISTS idx_students_course_id           ON public.students(course_id);
CREATE INDEX IF NOT EXISTS idx_students_access_code         ON public.students(access_code);
CREATE INDEX IF NOT EXISTS idx_students_cedula              ON public.students(cedula);
CREATE INDEX IF NOT EXISTS idx_sessions_student_id          ON public.sessions(student_id);
CREATE INDEX IF NOT EXISTS idx_sessions_course_id           ON public.sessions(course_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status              ON public.sessions(status);
CREATE INDEX IF NOT EXISTS idx_sessions_started_at          ON public.sessions(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_scenario_results_session_id  ON public.scenario_results(session_id);
CREATE INDEX IF NOT EXISTS idx_scenario_results_scenario_id ON public.scenario_results(scenario_id);


-- =============================================================
-- 8. ROW LEVEL SECURITY POLICIES
-- =============================================================

-- ── profiles ──────────────────────────────────────────────
CREATE POLICY "profiles: own read"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "profiles: own insert"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles: own update"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);


-- ── courses ───────────────────────────────────────────────
CREATE POLICY "courses: professor sees own"
    ON public.courses FOR SELECT TO authenticated
    USING (professor_id = auth.uid());

CREATE POLICY "courses: professor inserts own"
    ON public.courses FOR INSERT TO authenticated
    WITH CHECK (professor_id = auth.uid());

CREATE POLICY "courses: professor updates own"
    ON public.courses FOR UPDATE TO authenticated
    USING (professor_id = auth.uid());

CREATE POLICY "courses: professor deletes own"
    ON public.courses FOR DELETE TO authenticated
    USING (professor_id = auth.uid());


-- ── students ──────────────────────────────────────────────
-- Authenticated professors see only students in their own courses
CREATE POLICY "students: professor sees own"
    ON public.students FOR SELECT TO authenticated
    USING (
        course_id IN (
            SELECT id FROM public.courses WHERE professor_id = auth.uid()
        )
    );

CREATE POLICY "students: professor inserts own"
    ON public.students FOR INSERT TO authenticated
    WITH CHECK (
        course_id IN (
            SELECT id FROM public.courses WHERE professor_id = auth.uid()
        )
    );

CREATE POLICY "students: professor updates own"
    ON public.students FOR UPDATE TO authenticated
    USING (
        course_id IN (
            SELECT id FROM public.courses WHERE professor_id = auth.uid()
        )
    );

CREATE POLICY "students: professor deletes own"
    ON public.students FOR DELETE TO authenticated
    USING (
        course_id IN (
            SELECT id FROM public.courses WHERE professor_id = auth.uid()
        )
    );

-- Simulator (anon key) can look up active students by access_code
CREATE POLICY "students: anon reads active"
    ON public.students FOR SELECT TO anon
    USING (active = TRUE);


-- ── sessions ──────────────────────────────────────────────
-- Professors see sessions linked to their courses
CREATE POLICY "sessions: professor sees own"
    ON public.sessions FOR SELECT TO authenticated
    USING (
        course_id IN (
            SELECT id FROM public.courses WHERE professor_id = auth.uid()
        )
    );

-- Simulator creates sessions (anon or authenticated)
CREATE POLICY "sessions: anyone inserts"
    ON public.sessions FOR INSERT
    WITH CHECK (TRUE);

-- Simulator updates the session it just created (trusts session id stored client-side)
CREATE POLICY "sessions: anyone updates"
    ON public.sessions FOR UPDATE
    USING (TRUE);


-- ── scenario_results ──────────────────────────────────────
-- Professors see results for sessions in their courses
CREATE POLICY "scenario_results: professor sees own"
    ON public.scenario_results FOR SELECT TO authenticated
    USING (
        session_id IN (
            SELECT s.id
            FROM   public.sessions  s
            JOIN   public.courses   c ON c.id = s.course_id
            WHERE  c.professor_id = auth.uid()
        )
    );

-- Simulator inserts results
CREATE POLICY "scenario_results: anyone inserts"
    ON public.scenario_results FOR INSERT
    WITH CHECK (TRUE);


-- =============================================================
-- 9. FUNCTION: get_course_summary(course_id)
--    Returns aggregated statistics for a single course.
-- =============================================================
CREATE OR REPLACE FUNCTION public.get_course_summary(p_course_id UUID)
RETURNS TABLE (
    total_students       BIGINT,
    active_students      BIGINT,
    total_sessions       BIGINT,
    completed_sessions   BIGINT,
    in_progress_sessions BIGINT,
    abandoned_sessions   BIGINT,
    avg_score            NUMERIC,
    avg_scenarios_completed NUMERIC,
    total_wrong_attempts BIGINT,
    completion_rate      NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT
        COUNT(DISTINCT st.id)                                                              AS total_students,
        COUNT(DISTINCT st.id) FILTER (WHERE st.active)                                    AS active_students,
        COUNT(DISTINCT se.id)                                                              AS total_sessions,
        COUNT(DISTINCT se.id) FILTER (WHERE se.status = 'completed')                      AS completed_sessions,
        COUNT(DISTINCT se.id) FILTER (WHERE se.status = 'in_progress')                    AS in_progress_sessions,
        COUNT(DISTINCT se.id) FILTER (WHERE se.status = 'abandoned')                      AS abandoned_sessions,
        ROUND(AVG(se.total_score)          FILTER (WHERE se.status = 'completed'), 2)     AS avg_score,
        ROUND(AVG(se.scenarios_completed)  FILTER (WHERE se.status = 'completed'), 2)     AS avg_scenarios_completed,
        COALESCE(SUM(se.total_wrong_attempts), 0)                                          AS total_wrong_attempts,
        CASE
            WHEN COUNT(DISTINCT st.id) = 0 THEN 0
            ELSE ROUND(
                COUNT(DISTINCT se.student_id) FILTER (WHERE se.status = 'completed')
                * 100.0 / COUNT(DISTINCT st.id),
                2
            )
        END                                                                                AS completion_rate
    FROM  public.courses  c
    LEFT JOIN public.students st ON st.course_id = c.id
    LEFT JOIN public.sessions se ON se.course_id = c.id
    WHERE c.id = p_course_id
    GROUP BY c.id;
$$;


-- =============================================================
-- 10. TRIGGER: auto-create profile row when a new user signs up
-- =============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, email, name, role)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
        'professor'
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();


-- =============================================================
-- End of schema.sql
-- =============================================================
