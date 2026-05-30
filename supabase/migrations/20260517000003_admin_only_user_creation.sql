-- =============================================================================
-- Migración: 003 - Restricción de creación de cuentas a administradores
-- Descripción: Solo administradores pueden crear cuentas.
--              El registro público está deshabilitado en config.toml
--              mediante enable_signup = false (primera línea de defensa).
--              Aquí se añaden refuerzos en la capa de base de datos:
--                1. Mejora del trigger handle_new_user: el admin puede asignar
--                   cualquier rol pasando metadata.rol al crear el usuario.
--                2. Política DELETE solo para admins en profiles.
--                3. Política UPDATE propia sin permitir cambio de rol_id
--                   (previene auto-escalada de privilegios).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- NOTA IMPORTANTE:
-- El schema `auth` es gestionado exclusivamente por Supabase y no puede
-- modificarse desde migraciones de usuario. El bloqueo de registro público
-- se realiza en config.toml con `enable_signup = false`.
-- La creación de usuarios solo es posible vía:
--   - Supabase Admin API con service_role key (backend)
--   - Supabase Dashboard → Authentication → Add user
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- 1. REEMPLAZAR handle_new_user: El admin puede asignar un rol específico
--    pasando metadata.rol al crear el usuario.
--    Roles válidos: 'admin' | 'trabajador' | 'cliente' (default: 'cliente')
--
--    Ejemplo desde el backend:
--      await supabase.auth.admin.createUser({
--        email, password,
--        user_metadata: { nombre, apellido, telefono, rol: 'trabajador' }
--      })
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rol_id     SMALLINT;
    v_rol_nombre TEXT;
BEGIN
    -- Leer el rol solicitado en los metadatos
    v_rol_nombre := LOWER(TRIM(NEW.raw_user_meta_data ->> 'rol'));

    -- Buscar el id del rol solicitado
    SELECT id INTO v_rol_id
    FROM public.roles
    WHERE nombre = v_rol_nombre
    LIMIT 1;

    -- Si el rol no es válido o no se especificó, asignar 'cliente' por defecto
    IF v_rol_id IS NULL THEN
        SELECT id INTO v_rol_id
        FROM public.roles
        WHERE nombre = 'cliente'
        LIMIT 1;
    END IF;

    -- Crear el perfil del nuevo usuario
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
        COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data ->> 'nombre'),   ''), 'Sin nombre'),
        COALESCE(NULLIF(TRIM(NEW.raw_user_meta_data ->> 'apellido'), ''), 'Sin apellido'),
        NEW.email,
        NULLIF(TRIM(COALESCE(NEW.raw_user_meta_data ->> 'telefono', '')), '')
    );

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user IS
    'Crea automáticamente un perfil en public.profiles al registrar un usuario. '
    'El administrador puede especificar el rol en user_metadata.rol '
    '(admin | trabajador | cliente). Si no se especifica, se asigna ''cliente''. '
    'El registro público está deshabilitado en config.toml (enable_signup = false).';

-- -----------------------------------------------------------------------------
-- 2. POLÍTICA: Solo administradores pueden ELIMINAR perfiles
-- -----------------------------------------------------------------------------
CREATE POLICY "profiles_delete_admin"
    ON public.profiles
    FOR DELETE
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

-- -----------------------------------------------------------------------------
-- 3. POLÍTICA UPDATE propia: el usuario puede editar sus datos pero NO su rol_id
--    Previene auto-escalada de privilegios (un usuario cambiándose a admin).
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (
        auth.uid() = id
        AND rol_id = (SELECT rol_id FROM public.profiles WHERE id = auth.uid())
    );
