-- =============================================
-- MÓDULO GASTOS - 18D JOYEROS
-- =============================================

-- 1. Tabla de Gastos
CREATE TABLE gastos (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  fecha       DATE NOT NULL DEFAULT CURRENT_DATE,
  descripcion TEXT NOT NULL,
  tipo_pago   TEXT NOT NULL CHECK (tipo_pago IN ('efectivo', 'transferencia')),
  valor       INT NOT NULL CHECK (valor > 0),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Índices
CREATE INDEX idx_gastos_fecha      ON gastos(fecha DESC);
CREATE INDEX idx_gastos_tipo_pago  ON gastos(tipo_pago);

-- 3. Row Level Security
ALTER TABLE gastos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Usuarios autenticados pueden ver gastos"
ON gastos FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Usuarios autenticados pueden crear gastos"
ON gastos FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Usuarios autenticados pueden actualizar gastos"
ON gastos FOR UPDATE
TO authenticated
USING (true);

CREATE POLICY "Usuarios autenticados pueden eliminar gastos"
ON gastos FOR DELETE
TO authenticated
USING (true);
