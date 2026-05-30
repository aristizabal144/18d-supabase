-- =============================================================================
-- Migración: 002 - Tabla de Perfiles de Usuario (Extensión de auth.users)
-- Descripción: Crea la tabla pública de perfiles vinculada a auth.users.
--              NO modifica auth.users directamente (buena práctica Supabase).
--              Incluye trigger para creación automática al registrarse.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLA: public.profiles
-- La columna `id` es FK a auth.users(id) y también actúa como PK.
-- ON DELETE CASCADE garantiza que si el usuario es eliminado de auth,
-- su perfil también se elimina automáticamente.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    rol_id     SMALLINT    NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
    nombre     TEXT        NOT NULL CHECK (CHAR_LENGTH(TRIM(nombre)) > 0),
    apellido   TEXT        NOT NULL CHECK (CHAR_LENGTH(TRIM(apellido)) > 0),
    email      TEXT        NOT NULL UNIQUE CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    telefono   TEXT                 CHECK (telefono IS NULL OR telefono ~ '^\+?[0-9\s\-\(\)]{7,20}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT profiles_pkey PRIMARY KEY (id)
);

COMMENT ON TABLE  public.profiles              IS 'Perfil público de cada usuario. Extiende auth.users con datos de la aplicación.';
COMMENT ON COLUMN public.profiles.id          IS 'UUID del usuario proveniente de auth.users. Actúa como PK y FK.';
COMMENT ON COLUMN public.profiles.rol_id      IS 'FK al rol asignado al usuario (admin, trabajador, cliente).';
COMMENT ON COLUMN public.profiles.nombre      IS 'Nombre(s) del usuario.';
COMMENT ON COLUMN public.profiles.apellido    IS 'Apellido(s) del usuario.';
COMMENT ON COLUMN public.profiles.email       IS 'Correo electrónico del usuario. Debe coincidir con auth.users.email.';
COMMENT ON COLUMN public.profiles.telefono    IS 'Número de teléfono opcional del usuario.';
COMMENT ON COLUMN public.profiles.created_at  IS 'Fecha y hora de creación del perfil.';
COMMENT ON COLUMN public.profiles.updated_at  IS 'Fecha y hora de la última actualización del perfil.';

-- Nota sobre contraseña:
-- La contraseña NO se almacena en esta tabla. Supabase Auth la gestiona
-- de forma segura (bcrypt) dentro de auth.users. Almacenar contraseñas
-- en public.profiles sería una grave vulnerabilidad de seguridad.

-- -----------------------------------------------------------------------------
-- 2. ÍNDICES para mejorar el rendimiento de consultas frecuentes
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_profiles_rol_id  ON public.profiles(rol_id);
CREATE INDEX IF NOT EXISTS idx_profiles_email   ON public.profiles(email);

-- -----------------------------------------------------------------------------
-- 3. TRIGGER: Actualizar updated_at automáticamente
--    Reutiliza la función set_updated_at() creada en la migración anterior.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- 4. FUNCIÓN + TRIGGER: Crear perfil automáticamente al registrar un usuario
--    Se ejecuta AFTER INSERT ON auth.users. Asigna el rol 'cliente' por defecto.
--    security definer: corre con privilegios del owner para saltear RLS durante
--    el proceso de registro, garantizando que el perfil siempre se cree.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rol_id SMALLINT;
BEGIN
    -- Obtener el ID del rol 'cliente' (rol por defecto al registrarse)
    SELECT id INTO v_rol_id
    FROM public.roles
    WHERE nombre = 'cliente'
    LIMIT 1;

    -- Insertar el perfil usando los metadatos pasados durante el registro.
    -- Los metadatos se envían desde el cliente en: supabase.auth.signUp({ data: { ... } })
    INSERT INTO public.profiles (
        id,
        rol_id,
        nombre,
        apellido,
        email,
        telefono
    )
    VALUES (
        NEW.id,
        v_rol_id,
        COALESCE(NEW.raw_user_meta_data ->> 'nombre',   'Sin nombre'),
        COALESCE(NEW.raw_user_meta_data ->> 'apellido', 'Sin apellido'),
        NEW.email,
        NEW.raw_user_meta_data ->> 'telefono'  -- puede ser NULL
    );

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user IS
    'Crea automáticamente un perfil en public.profiles cada vez que se registra '
    'un nuevo usuario en auth.users. Asigna el rol "cliente" por defecto. '
    'Usa metadata enviada desde el cliente durante el signup.';

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- -----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Los usuarios pueden ver y actualizar su propio perfil
CREATE POLICY "profiles_select_own"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY "profiles_update_own"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Los administradores pueden ver todos los perfiles
-- (se verifica el rol consultando el propio profiles, evitando recursión con SECURITY DEFINER)
CREATE POLICY "profiles_select_admin"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.profiles p
            JOIN public.roles r ON r.id = p.rol_id
            WHERE p.id = auth.uid()
              AND r.nombre = 'admin'
        )
    );

-- Los administradores pueden actualizar cualquier perfil
CREATE POLICY "profiles_update_admin"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1
            FROM public.profiles p
            JOIN public.roles r ON r.id = p.rol_id
            WHERE p.id = auth.uid()
              AND r.nombre = 'admin'
        )
    )
    WITH CHECK (true);

-- El service_role tiene acceso total (para operaciones administrativas del backend)
CREATE POLICY "profiles_all_service_role"
    ON public.profiles
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);
