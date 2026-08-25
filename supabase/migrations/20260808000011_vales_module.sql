-- ==============================================================================
-- MIGRACIÓN DE SUPABASE: Módulo de Vales y Préstamos (18D Joyeros)
-- ==============================================================================

-- 1. Tabla de Vales / Préstamos
CREATE TABLE IF NOT EXISTS public.vales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    beneficiario TEXT NOT NULL,
    concepto TEXT NOT NULL,
    monto_total NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (monto_total >= 0),
    monto_abonado NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (monto_abonado >= 0),
    saldo_pendiente NUMERIC(12, 2) GENERATED ALWAYS AS (GREATEST(0, monto_total - monto_abonado)) STORED,
    estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'parcial', 'cancelado')),
    fecha_emision TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Tabla de Abonos a Vales
CREATE TABLE IF NOT EXISTS public.abonos_vales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vale_id UUID NOT NULL REFERENCES public.vales(id) ON DELETE CASCADE,
    valor NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (valor > 0),
    tipo_pago TEXT NOT NULL DEFAULT 'efectivo' CHECK (tipo_pago IN ('efectivo', 'transferencia')),
    notas TEXT,
    fecha TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Índices para optimizar consultas
CREATE INDEX IF NOT EXISTS idx_vales_usuario_id ON public.vales(usuario_id);
CREATE INDEX IF NOT EXISTS idx_vales_estado ON public.vales(estado);
CREATE INDEX IF NOT EXISTS idx_abonos_vales_vale_id ON public.abonos_vales(vale_id);

-- 4. Trigger para actualizar el monto_abonado y el estado del vale automáticamente al insertar/eliminar abonos
CREATE OR REPLACE FUNCTION public.recalcular_estado_vale()
RETURNS TRIGGER AS $$
DECLARE
    total_abonos NUMERIC(12, 2);
    total_vale NUMERIC(12, 2);
    target_vale_id UUID;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        target_vale_id := OLD.vale_id;
    ELSE
        target_vale_id := NEW.vale_id;
    END IF;

    -- Obtener la suma acumulada de abonos
    SELECT COALESCE(SUM(valor), 0) INTO total_abonos
    FROM public.abonos_vales
    WHERE vale_id = target_vale_id;

    -- Obtener el monto total del vale
    SELECT monto_total INTO total_vale
    FROM public.vales
    WHERE id = target_vale_id;

    -- Actualizar monto_abonado y estado en la tabla vales
    UPDATE public.vales
    SET 
        monto_abonado = total_abonos,
        estado = CASE 
            WHEN total_abonos >= total_vale THEN 'cancelado'
            WHEN total_abonos > 0 THEN 'parcial'
            ELSE 'pendiente'
        END,
        updated_at = NOW()
    WHERE id = target_vale_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Disparadores
DROP TRIGGER IF EXISTS trigger_recalcular_vale_aiu ON public.abonos_vales;
CREATE TRIGGER trigger_recalcular_vale_aiu
AFTER INSERT OR UPDATE ON public.abonos_vales
FOR EACH ROW EXECUTE FUNCTION public.recalcular_estado_vale();

DROP TRIGGER IF EXISTS trigger_recalcular_vale_ad ON public.abonos_vales;
CREATE TRIGGER trigger_recalcular_vale_ad
AFTER DELETE ON public.abonos_vales
FOR EACH ROW EXECUTE FUNCTION public.recalcular_estado_vale();

-- 5. Políticas RLS (Row Level Security)
ALTER TABLE public.vales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.abonos_vales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir todo en vales" ON public.vales;
CREATE POLICY "Permitir todo en vales" ON public.vales FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Permitir todo en abonos_vales" ON public.abonos_vales;
CREATE POLICY "Permitir todo en abonos_vales" ON public.abonos_vales FOR ALL USING (true) WITH CHECK (true);
