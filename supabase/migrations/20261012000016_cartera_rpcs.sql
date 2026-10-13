-- =============================================================================
-- Migración: 016 - Cartera agregada en el servidor
-- Descripción: Mueve los cálculos de cartera (facturado, abonado, saldos por
--              cliente y por pedido) a funciones SQL. El frontend recibe
--              totales y páginas ya calculadas en lugar de descargar todos los
--              pedidos y abonos, lo que escala a miles de registros y evita el
--              límite de filas de PostgREST y URLs largas con filtros IN.
--              Las funciones son SECURITY INVOKER: respetan el RLS existente.
-- Fecha: 2026-10-12
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ÍNDICES
--    Parciales sobre pedidos entregados (los únicos que entran en cartera).
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pedidos_entregados_fecha
    ON public.pedidos (fecha_entregado)
    WHERE estado = 'entregado';

CREATE INDEX IF NOT EXISTS idx_pedidos_entregados_cliente
    ON public.pedidos (cliente_id, fecha_entregado)
    WHERE estado = 'entregado';

CREATE INDEX IF NOT EXISTS idx_abonos_pedido_valor
    ON public.abonos (pedido_id) INCLUDE (valor, tipo_pago);

-- -----------------------------------------------------------------------------
-- 2. BASE: un registro por pedido entregado con sus abonos agregados
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cartera_pedidos_base(
    p_desde      DATE DEFAULT NULL,
    p_hasta      DATE DEFAULT NULL,
    p_cliente_id UUID DEFAULT NULL,
    p_busqueda   TEXT DEFAULT NULL
)
RETURNS TABLE (
    pedido_id           UUID,
    cliente_id          UUID,
    total_pedido        BIGINT,
    total_abonado       BIGINT,
    total_efectivo      BIGINT,
    total_transferencia BIGINT,
    saldo_pendiente     BIGINT
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT
        p.id,
        p.cliente_id,
        COALESCE(p.total_pedido, 0)::BIGINT,
        COALESCE(a.total, 0),
        COALESCE(a.efectivo, 0),
        COALESCE(a.transferencia, 0),
        COALESCE(p.total_pedido, 0)::BIGINT - COALESCE(a.total, 0)
    FROM public.pedidos p
    LEFT JOIN LATERAL (
        SELECT
            SUM(ab.valor)::BIGINT                                              AS total,
            (SUM(ab.valor) FILTER (WHERE ab.tipo_pago = 'efectivo'))::BIGINT      AS efectivo,
            (SUM(ab.valor) FILTER (WHERE ab.tipo_pago = 'transferencia'))::BIGINT AS transferencia
        FROM public.abonos ab
        WHERE ab.pedido_id = p.id
    ) a ON TRUE
    WHERE p.estado = 'entregado'
      AND (p_desde IS NULL OR p.fecha_entregado >= p_desde)
      AND (p_hasta IS NULL OR p.fecha_entregado <= p_hasta)
      AND (p_cliente_id IS NULL OR p.cliente_id = p_cliente_id)
      AND (
          NULLIF(TRIM(p_busqueda), '') IS NULL
          OR EXISTS (
              SELECT 1
              FROM public.profiles pr
              WHERE pr.id = p.cliente_id
                AND CONCAT_WS(' ', pr.nombre, pr.apellido) ILIKE '%' || TRIM(p_busqueda) || '%'
          )
      );
$$;

COMMENT ON FUNCTION public.cartera_pedidos_base IS 'Pedidos entregados con abonos agregados (total, efectivo, transferencia y saldo). Base de las demás funciones de cartera.';

-- -----------------------------------------------------------------------------
-- 3. RESUMEN: KPIs globales de cartera para los filtros dados
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_cartera_resumen(
    p_desde      DATE DEFAULT NULL,
    p_hasta      DATE DEFAULT NULL,
    p_cliente_id UUID DEFAULT NULL,
    p_busqueda   TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    WITH base AS (
        SELECT * FROM public.cartera_pedidos_base(p_desde, p_hasta, p_cliente_id, p_busqueda)
    ),
    por_cliente AS (
        SELECT cliente_id, SUM(saldo_pendiente) AS saldo
        FROM base
        GROUP BY cliente_id
    )
    SELECT json_build_object(
        'total_facturado',     COALESCE((SELECT SUM(total_pedido) FROM base), 0),
        'total_recaudado',     COALESCE((SELECT SUM(total_abonado) FROM base), 0),
        'total_efectivo',      COALESCE((SELECT SUM(total_efectivo) FROM base), 0),
        'total_transferencia', COALESCE((SELECT SUM(total_transferencia) FROM base), 0),
        'total_pendiente',     COALESCE((SELECT SUM(saldo_pendiente) FROM base), 0),
        'total_pedidos',       (SELECT COUNT(*) FROM base),
        'pedidos_con_saldo',   (SELECT COUNT(*) FROM base WHERE saldo_pendiente > 0),
        'total_clientes',      (SELECT COUNT(*) FROM por_cliente),
        'clientes_con_saldo',  (SELECT COUNT(*) FROM por_cliente WHERE saldo > 0),
        'clientes_al_dia',     (SELECT COUNT(*) FROM por_cliente WHERE saldo <= 0)
    );
$$;

COMMENT ON FUNCTION public.get_cartera_resumen IS 'KPIs de cartera: facturado, recaudado (efectivo/transferencia), pendiente y conteos de clientes y pedidos.';

-- -----------------------------------------------------------------------------
-- 4. CLIENTES: cartera agrupada por cliente, filtrada, ordenada y paginada
--    p_estado: 'todos' | 'con_saldo' | 'al_dia'
--    p_orden:  'cliente' | 'pedidos_count' | 'total_pedidos' | 'total_abonado'
--              | 'saldo_pendiente' | 'porcentaje_cobrado'
--    total_count trae el total de filas (sin paginar) para la paginación.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_cartera_clientes(
    p_desde      DATE    DEFAULT NULL,
    p_hasta      DATE    DEFAULT NULL,
    p_cliente_id UUID    DEFAULT NULL,
    p_busqueda   TEXT    DEFAULT NULL,
    p_estado     TEXT    DEFAULT 'todos',
    p_orden      TEXT    DEFAULT 'saldo_pendiente',
    p_desc       BOOLEAN DEFAULT TRUE,
    p_limit      INT     DEFAULT 25,
    p_offset     INT     DEFAULT 0
)
RETURNS TABLE (
    cliente_id          UUID,
    nombre              TEXT,
    apellido            TEXT,
    pedidos_count       BIGINT,
    pedidos_con_saldo   BIGINT,
    total_pedidos       BIGINT,
    total_abonado       BIGINT,
    total_efectivo      BIGINT,
    total_transferencia BIGINT,
    saldo_pendiente     BIGINT,
    porcentaje_cobrado  INT,
    total_count         BIGINT
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    WITH base AS (
        SELECT * FROM public.cartera_pedidos_base(p_desde, p_hasta, p_cliente_id, p_busqueda)
    ),
    agg AS (
        SELECT
            b.cliente_id,
            COUNT(*)                                     AS pedidos_count,
            COUNT(*) FILTER (WHERE b.saldo_pendiente > 0) AS pedidos_con_saldo,
            SUM(b.total_pedido)::BIGINT                  AS total_pedidos,
            SUM(b.total_abonado)::BIGINT                 AS total_abonado,
            SUM(b.total_efectivo)::BIGINT                AS total_efectivo,
            SUM(b.total_transferencia)::BIGINT           AS total_transferencia,
            SUM(b.saldo_pendiente)::BIGINT               AS saldo_pendiente
        FROM base b
        GROUP BY b.cliente_id
    ),
    filtrado AS (
        SELECT
            a.*,
            COALESCE(pr.nombre, '')   AS nombre,
            COALESCE(pr.apellido, '') AS apellido,
            CASE
                WHEN a.total_pedidos > 0
                    THEN LEAST(100, ROUND(a.total_abonado * 100.0 / a.total_pedidos))::INT
                ELSE 0
            END AS porcentaje_cobrado
        FROM agg a
        LEFT JOIN public.profiles pr ON pr.id = a.cliente_id
        WHERE COALESCE(p_estado, 'todos') = 'todos'
           OR (p_estado = 'con_saldo' AND a.saldo_pendiente > 0)
           OR (p_estado = 'al_dia'    AND a.saldo_pendiente <= 0)
    ),
    ordenable AS (
        SELECT
            f.*,
            CASE p_orden
                WHEN 'pedidos_count'      THEN f.pedidos_count::NUMERIC
                WHEN 'total_pedidos'      THEN f.total_pedidos::NUMERIC
                WHEN 'total_abonado'      THEN f.total_abonado::NUMERIC
                WHEN 'porcentaje_cobrado' THEN f.porcentaje_cobrado::NUMERIC
                WHEN 'cliente'            THEN NULL
                ELSE f.saldo_pendiente::NUMERIC
            END AS orden_num,
            LOWER(f.nombre || ' ' || f.apellido) AS orden_nombre
        FROM filtrado f
    )
    SELECT
        o.cliente_id, o.nombre, o.apellido,
        o.pedidos_count, o.pedidos_con_saldo,
        o.total_pedidos, o.total_abonado, o.total_efectivo, o.total_transferencia,
        o.saldo_pendiente, o.porcentaje_cobrado,
        COUNT(*) OVER () AS total_count
    FROM ordenable o
    ORDER BY
        CASE WHEN p_orden = 'cliente' AND NOT p_desc THEN o.orden_nombre END ASC,
        CASE WHEN p_orden = 'cliente' AND p_desc     THEN o.orden_nombre END DESC,
        CASE WHEN NOT p_desc THEN o.orden_num END ASC,
        CASE WHEN p_desc     THEN o.orden_num END DESC,
        o.orden_nombre ASC,
        o.cliente_id
    LIMIT p_limit
    OFFSET GREATEST(p_offset, 0);
$$;

COMMENT ON FUNCTION public.get_cartera_clientes IS 'Cartera por cliente con filtro de estado, búsqueda, orden y paginación (total_count = filas totales). p_limit NULL devuelve todo.';

-- -----------------------------------------------------------------------------
-- 5. PEDIDOS DE UN CLIENTE: detalle de cartera por pedido
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_cartera_pedidos_cliente(
    p_cliente_id UUID,
    p_desde      DATE DEFAULT NULL,
    p_hasta      DATE DEFAULT NULL
)
RETURNS TABLE (
    id                  UUID,
    referencia          TEXT,
    titulo              TEXT,
    fecha_entregado     DATE,
    total_pedido        BIGINT,
    total_abonado       BIGINT,
    total_efectivo      BIGINT,
    total_transferencia BIGINT,
    saldo_pendiente     BIGINT
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT
        p.id, p.referencia::TEXT, p.titulo::TEXT, p.fecha_entregado::DATE,
        b.total_pedido, b.total_abonado, b.total_efectivo, b.total_transferencia, b.saldo_pendiente
    FROM public.cartera_pedidos_base(p_desde, p_hasta, p_cliente_id, NULL) b
    JOIN public.pedidos p ON p.id = b.pedido_id
    ORDER BY p.fecha_entregado DESC NULLS LAST, p.referencia;
$$;

COMMENT ON FUNCTION public.get_cartera_pedidos_cliente IS 'Pedidos entregados de un cliente con total, abonos (efectivo/transferencia) y saldo.';

-- -----------------------------------------------------------------------------
-- 6. PERMISOS: solo usuarios autenticados
-- -----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.cartera_pedidos_base(DATE, DATE, UUID, TEXT)                                      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cartera_resumen(DATE, DATE, UUID, TEXT)                                       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cartera_clientes(DATE, DATE, UUID, TEXT, TEXT, TEXT, BOOLEAN, INT, INT)        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cartera_pedidos_cliente(UUID, DATE, DATE)                                     FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.cartera_pedidos_base(DATE, DATE, UUID, TEXT)                                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cartera_resumen(DATE, DATE, UUID, TEXT)                                        TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cartera_clientes(DATE, DATE, UUID, TEXT, TEXT, TEXT, BOOLEAN, INT, INT)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cartera_pedidos_cliente(UUID, DATE, DATE)                                      TO authenticated;

-- =============================================================================
-- FIN DE MIGRACIÓN
-- =============================================================================
