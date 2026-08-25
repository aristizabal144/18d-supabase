-- ==============================================================================
-- MIGRACIÓN: Agregar cliente_id a la tabla arreglos
-- ==============================================================================

ALTER TABLE public.arreglos
ADD COLUMN IF NOT EXISTS cliente_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_arreglos_cliente_id ON public.arreglos(cliente_id);
