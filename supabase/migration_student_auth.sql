-- =============================================================
--  SimLab · Migración 2: Autenticación de estudiantes
--  Corre este script en el SQL Editor de Supabase
--  DESPUÉS de haber corrido schema.sql
-- =============================================================

-- =============================================================
-- 1. Agregar columnas de estudiante a profiles
-- =============================================================
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS expediente        BIGINT UNIQUE,
  ADD COLUMN IF NOT EXISTS apellido          TEXT,
  ADD COLUMN IF NOT EXISTS periodo_academico TEXT,
  ADD COLUMN IF NOT EXISTS seccion           TEXT;

-- Actualizar el constraint de rol para incluir 'student'
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('admin', 'professor', 'student'));


-- =============================================================
-- 2. Actualizar trigger handle_new_user
--    Ahora lee los campos del estudiante del metadata de Auth
-- =============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (
        id, email, name, apellido,
        expediente, periodo_academico, seccion, role
    )
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'nombre',
                 split_part(NEW.email, '@', 1)),
        NEW.raw_user_meta_data->>'apellido',
        CASE
            WHEN NEW.raw_user_meta_data->>'expediente' IS NOT NULL
            THEN (NEW.raw_user_meta_data->>'expediente')::BIGINT
            ELSE NULL
        END,
        NEW.raw_user_meta_data->>'periodo_academico',
        NEW.raw_user_meta_data->>'seccion',
        COALESCE(NEW.raw_user_meta_data->>'role', 'student')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;


-- =============================================================
-- 3. Agregar profile_id a sessions (enlace directo al usuario)
-- =============================================================
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS profile_id UUID
    REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_profile_id
  ON public.sessions(profile_id);


-- =============================================================
-- 4. RLS adicional: estudiantes ven/insertan sus propias sesiones
-- =============================================================
DROP POLICY IF EXISTS "sessions: student sees own" ON public.sessions;
CREATE POLICY "sessions: student sees own"
    ON public.sessions FOR SELECT TO authenticated
    USING (profile_id = auth.uid());

-- Estudiantes pueden leer su propio perfil (ya cubierto por "own read")
-- Agregar permiso para que estudiantes puedan insertar su perfil al registrarse
DROP POLICY IF EXISTS "profiles: student insert" ON public.profiles;
CREATE POLICY "profiles: student insert"
    ON public.profiles FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = id);


-- =============================================================
-- 5. Crear usuario admin directamente en la BD
--    Usuario: admin  |  Contraseña: SimuladorSV26
-- =============================================================
DO $$
DECLARE
    _uid UUID := gen_random_uuid();
BEGIN
    -- Verificar si ya existe
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = 'admin@simlab.local') THEN
        RAISE NOTICE 'El usuario admin ya existe. Nada que hacer.';
        RETURN;
    END IF;

    -- Insertar en auth.users
    INSERT INTO auth.users (
        id, instance_id, aud, role, email,
        encrypted_password,
        email_confirmed_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, email_change,
        email_change_token_new, recovery_token
    ) VALUES (
        _uid,
        '00000000-0000-0000-0000-000000000000',
        'authenticated',
        'authenticated',
        'admin@simlab.local',
        crypt('SimuladorSV26', gen_salt('bf')),
        NOW(),
        '{"provider":"email","providers":["email"]}',
        '{"role":"admin","nombre":"Administrador"}',
        NOW(), NOW(),
        '', '', '', ''
    );

    -- Insertar identidad de email (necesario para que el login funcione)
    INSERT INTO auth.identities (
        id, user_id, identity_data, provider,
        last_sign_in_at, created_at, updated_at
    ) VALUES (
        gen_random_uuid(),
        _uid,
        jsonb_build_object('sub', _uid::text, 'email', 'admin@simlab.local'),
        'email',
        NOW(), NOW(), NOW()
    );

    -- Insertar perfil (el trigger debería hacerlo, pero lo forzamos por si acaso)
    INSERT INTO public.profiles (id, email, name, role)
    VALUES (_uid, 'admin@simlab.local', 'Administrador', 'admin')
    ON CONFLICT (id) DO NOTHING;

    RAISE NOTICE 'Usuario admin creado correctamente. ID: %', _uid;
END;
$$;


-- =============================================================
-- IMPORTANTE: Desactivar confirmación de email en Supabase
-- Para que el registro de estudiantes funcione sin correo real:
--   Authentication → Configuration → Email → desactiva
--   "Enable email confirmations"
-- =============================================================
