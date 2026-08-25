-- ==============================================================================
-- MIGRACIÓN DE SUPABASE: Módulo de Arreglos de Taller (18D Joyeros)
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.arreglos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    cantidad INTEGER NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    descripcion TEXT NOT NULL,
    valor NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (valor >= 0),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para optimizar consultas por fecha
CREATE INDEX IF NOT EXISTS idx_arreglos_fecha ON public.arreglos(fecha);
CREATE INDEX IF NOT EXISTS idx_arreglos_created_at ON public.arreglos(created_at);

-- Habilitar RLS
ALTER TABLE public.arreglos ENABLE ROW LEVEL SECURITY;

-- Políticas RLS
DROP POLICY IF EXISTS "Permitir todo en arreglos" ON public.arreglos;
CREATE POLICY "Permitir todo en arreglos" ON public.arreglos FOR ALL USING (true) WITH CHECK (true);
