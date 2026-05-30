-- =============================================================================
-- Migración: 004 - Fix Infinite Recursion en Políticas de Profiles
-- Descripción: Reemplaza las consultas directas a public.profiles dentro de 
--              las políticas RLS por funciones SECURITY DEFINER para evitar
--              el error de recursión infinita (infinite recursion detected).
-- =============================================================================

-- 1. Función para verificar si el usuario actual es admin (Bypassea RLS)
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER -- Se ejecuta con privilegios de administrador (postgres)
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN public.roles r ON p.rol_id = r.id
    WHERE p.id = auth.uid() AND r.nombre = 'admin'
  ) INTO v_is_admin;
  
  RETURN COALESCE(v_is_admin, false);
END;
$$;

-- 2. Función para obtener el rol actual del usuario sin disparar RLS
CREATE OR REPLACE FUNCTION public.get_user_role_id(user_id UUID)
RETURNS SMALLINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol_id SMALLINT;
BEGIN
  SELECT rol_id INTO v_rol_id FROM public.profiles WHERE id = user_id;
  RETURN v_rol_id;
END;
$$;

-- 3. Eliminar las políticas conflictivas
DROP POLICY IF EXISTS "profiles_select_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

-- 4. Recrear políticas usando las funciones seguras
CREATE POLICY "profiles_select_admin"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (public.is_admin());

CREATE POLICY "profiles_update_admin"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (true);

CREATE POLICY "profiles_delete_admin"
    ON public.profiles
    FOR DELETE
    TO authenticated
    USING (public.is_admin());

CREATE POLICY "profiles_update_own"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (
        auth.uid() = id
        AND rol_id = public.get_user_role_id(auth.uid()) -- Previene escalada de privilegios sin recursión
    );
