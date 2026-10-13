-- =============================================================================
-- Migración: 017 - Estado de pago en arreglos
-- Descripción: Cada arreglo queda 'pendiente' (por cobrar) o 'cancelado'
--              (pagado), con fecha y medio de pago para el cuadre de caja y
--              notas opcionales. Agrega funciones de resumen y de deudores
--              calculadas en el servidor y restringe la tabla a usuarios
--              autenticados (antes la política permitía acceso anónimo).
--              Los arreglos existentes quedan como 'pendiente'.
-- Fecha: 2026-10-12
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. COLUMNAS
-- -----------------------------------------------------------------------------
ALTER TABLE public.arreglos
    ADD COLUMN IF NOT EXISTS estado     TEXT NOT NULL DEFAULT 'pendiente',
    ADD COLUMN IF NOT EXISTS fecha_pago DATE,
    ADD COLUMN IF NOT EXISTS tipo_pago  TEXT,
    ADD COLUMN IF NOT EXISTS notas      TEXT;

ALTER TABLE public.arreglos
    DROP CONSTRAINT IF EXISTS arreglos_estado_check,
    DROP CONSTRAINT IF EXISTS arreglos_tipo_pago_check,
    DROP CONSTRAINT IF EXISTS arreglos_pago_consistente;

ALTER TABLE public.arreglos
    ADD CONSTRAINT arreglos_estado_check
        CHECK (estado IN ('pendiente', 'cancelado')),
    ADD CONSTRAINT arreglos_tipo_pago_check
        CHECK (tipo_pago IS NULL OR tipo_pago IN ('efectivo', 'transferencia')),
    -- Un arreglo cancelado siempre sabe cuándo y cómo se pagó; uno pendiente no tiene pago.
    ADD CONSTRAINT arreglos_pago_consistente
        CHECK (
            (estado = 'pendiente' AND fecha_pago IS NULL AND tipo_pago IS NULL)
            OR (estado = 'cancelado' AND fecha_pago IS NOT NULL AND tipo_pago IS NOT NULL)
        );

COMMENT ON COLUMN public.arreglos.estado     IS 'pendiente = por cobrar; cancelado = pagado por el cliente.';
COMMENT ON COLUMN public.arreglos.fecha_pago IS 'Fecha en que el cliente pagó el arreglo.';
COMMENT ON COLUMN public.arreglos.tipo_pago  IS 'Medio de pago: efectivo o transferencia.';
COMMENT ON COLUMN public.arreglos.notas      IS 'Observaciones internas del arreglo.';

-- -----------------------------------------------------------------------------
-- 2. ÍNDICES
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_arreglos_estado_fecha
    ON public.arreglos (estado, fecha DESC);

CREATE INDEX IF NOT EXISTS idx_arreglos_pendientes_cliente
    ON public.arreglos (cliente_id, fecha)
    WHERE estado = 'pendiente';

CREATE INDEX IF NOT EXISTS idx_arreglos_fecha_pago
    ON public.arreglos (fecha_pago)
    WHERE estado = 'cancelado';

-- -----------------------------------------------------------------------------
-- 3. RLS: solo usuarios autenticados (igual que gastos)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Permitir todo en arreglos" ON public.arreglos;
DROP POLICY IF EXISTS "arreglos_select_authenticated" ON public.arreglos;
DROP POLICY IF EXISTS "arreglos_insert_authenticated" ON public.arreglos;
DROP POLICY IF EXISTS "arreglos_update_authenticated" ON public.arreglos;
DROP POLICY IF EXISTS "arreglos_delete_authenticated" ON public.arreglos;

CREATE POLICY "arreglos_select_authenticated"
    ON public.arreglos FOR SELECT TO authenticated USING (true);

CREATE POLICY "arreglos_insert_authenticated"
    ON public.arreglos FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "arreglos_update_authenticated"
    ON public.arreglos FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "arreglos_delete_authenticated"
    ON public.arreglos FOR DELETE TO authenticated USING (true);

-- -----------------------------------------------------------------------------
-- 4. RESUMEN GLOBAL
--    p_hoy llega desde el navegador para que los cortes de mes y la antigüedad
--    usen la fecha local del negocio y no la de UTC del servidor.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_arreglos_resumen(
    p_hoy             DATE DEFAULT CURRENT_DATE,
    p_dias_vencimiento INT DEFAULT 30
)
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    WITH limites AS (
        SELECT
            date_trunc('month', p_hoy)::date                                   AS ini_mes,
            (date_trunc('month', p_hoy) + INTERVAL '1 month - 1 day')::date    AS fin_mes,
            (date_trunc('month', p_hoy) - INTERVAL '1 month')::date            AS ini_ant,
            (date_trunc('month', p_hoy) - INTERVAL '1 day')::date              AS fin_ant
    )
    SELECT json_build_object(
        'total_pendiente',           COALESCE(SUM(a.valor) FILTER (WHERE a.estado = 'pendiente'), 0),
        'cantidad_pendientes',       COUNT(*) FILTER (WHERE a.estado = 'pendiente'),
        'cantidad_cancelados',       COUNT(*) FILTER (WHERE a.estado = 'cancelado'),
        'cantidad_total',            COUNT(*),
        'clientes_con_deuda',        COUNT(DISTINCT a.cliente_id) FILTER (WHERE a.estado = 'pendiente'),
        'total_vencido',             COALESCE(SUM(a.valor) FILTER (WHERE a.estado = 'pendiente' AND a.fecha < p_hoy - p_dias_vencimiento), 0),
        'cantidad_vencidos',         COUNT(*) FILTER (WHERE a.estado = 'pendiente' AND a.fecha < p_hoy - p_dias_vencimiento),
        'cobrado_mes',               COALESCE(SUM(a.valor) FILTER (WHERE a.estado = 'cancelado' AND a.fecha_pago BETWEEN l.ini_mes AND l.fin_mes), 0),
        'cobrado_mes_efectivo',      COALESCE(SUM(a.valor) FILTER (WHERE a.estado = 'cancelado' AND a.tipo_pago = 'efectivo' AND a.fecha_pago BETWEEN l.ini_mes AND l.fin_mes), 0),
        'cobrado_mes_transferencia', COALESCE(SUM(a.valor) FILTER (WHERE a.estado = 'cancelado' AND a.tipo_pago = 'transferencia' AND a.fecha_pago BETWEEN l.ini_mes AND l.fin_mes), 0),
        'total_mes',                 COALESCE(SUM(a.valor) FILTER (WHERE a.fecha BETWEEN l.ini_mes AND l.fin_mes), 0),
        'cantidad_mes',              COUNT(*) FILTER (WHERE a.fecha BETWEEN l.ini_mes AND l.fin_mes),
        'piezas_mes',                COALESCE(SUM(a.cantidad) FILTER (WHERE a.fecha BETWEEN l.ini_mes AND l.fin_mes), 0),
        'total_mes_anterior',        COALESCE(SUM(a.valor) FILTER (WHERE a.fecha BETWEEN l.ini_ant AND l.fin_ant), 0),
        'total_historico',           COALESCE(SUM(a.valor), 0)
    )
    FROM limites l
    LEFT JOIN public.arreglos a ON TRUE;
$$;

-- -----------------------------------------------------------------------------
-- 5. DEUDORES: saldo pendiente agrupado por cliente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_arreglos_deudores(
    p_hoy DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    cliente_id        UUID,
    nombre            TEXT,
    apellido          TEXT,
    telefono          TEXT,
    cantidad          BIGINT,
    piezas            BIGINT,
    total             NUMERIC,
    fecha_mas_antigua DATE,
    dias_mas_antiguo  INT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    SELECT
        a.cliente_id,
        p.nombre,
        p.apellido,
        p.telefono,
        COUNT(*)            AS cantidad,
        SUM(a.cantidad)     AS piezas,
        SUM(a.valor)        AS total,
        MIN(a.fecha)        AS fecha_mas_antigua,
        (p_hoy - MIN(a.fecha))::int AS dias_mas_antiguo
    FROM public.arreglos a
    LEFT JOIN public.profiles p ON p.id = a.cliente_id
    WHERE a.estado = 'pendiente'
      AND a.cliente_id IS NOT NULL
    GROUP BY a.cliente_id, p.nombre, p.apellido, p.telefono
    ORDER BY SUM(a.valor) DESC;
$$;

-- -----------------------------------------------------------------------------
-- 6. PERMISOS
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.get_arreglos_resumen(DATE, INT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_arreglos_deudores(DATE)     FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_arreglos_resumen(DATE, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_arreglos_deudores(DATE)     TO authenticated;
