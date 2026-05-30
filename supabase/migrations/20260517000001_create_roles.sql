-- =============================================================================
-- Migración: 001 - Tabla de Roles
-- Descripción: Crea la tabla de roles del sistema y siembra los roles iniciales.
-- Roles disponibles: admin, trabajador, cliente
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLA: public.roles
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.roles (
    id          SMALLINT    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      TEXT        NOT NULL UNIQUE,
    descripcion TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.roles              IS 'Roles del sistema para control de acceso (RBAC).';
COMMENT ON COLUMN public.roles.id          IS 'Identificador único del rol.';
COMMENT ON COLUMN public.roles.nombre      IS 'Nombre único del rol (admin, trabajador, cliente).';
COMMENT ON COLUMN public.roles.descripcion IS 'Descripción opcional del rol.';
COMMENT ON COLUMN public.roles.created_at  IS 'Fecha y hora de creación del registro.';
COMMENT ON COLUMN public.roles.updated_at  IS 'Fecha y hora de la última actualización.';

-- -----------------------------------------------------------------------------
-- 2. TRIGGER: Actualizar updated_at automáticamente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at IS 'Función reutilizable que actualiza la columna updated_at al momento actual antes de cada UPDATE.';

CREATE TRIGGER trg_roles_updated_at
    BEFORE UPDATE ON public.roles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- 3. DATOS SEMILLA (Seed): Roles iniciales del sistema
-- -----------------------------------------------------------------------------
INSERT INTO public.roles (nombre, descripcion)
VALUES
    ('admin',      'Administrador del sistema con acceso completo.'),
    ('trabajador', 'Empleado con acceso a operaciones del negocio.'),
    ('cliente',    'Usuario final que consume los servicios.')
ON CONFLICT (nombre) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

-- Cualquier usuario autenticado puede leer los roles (necesario para joins y selects)
CREATE POLICY "roles_select_authenticated"
    ON public.roles
    FOR SELECT
    TO authenticated
    USING (true);

-- Solo el rol de servicio (service_role) puede modificar roles
-- Los cambios de roles se hacen exclusivamente desde el backend o migraciones
CREATE POLICY "roles_all_service_role"
    ON public.roles
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);
