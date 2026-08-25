-- =============================================
-- MÓDULO ABONOS - 18D JOYEROS
-- =============================================

-- 1. Tabla de Abonos
CREATE TABLE abonos (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pedido_id   UUID NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  valor       INT NOT NULL CHECK (valor <> 0),  -- en COP, puede ser negativo? No, solo positivo
  tipo_pago   TEXT NOT NULL CHECK (tipo_pago IN ('efectivo', 'transferencia')),
  fecha       DATE NOT NULL DEFAULT CURRENT_DATE,
  notas       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Índices
CREATE INDEX idx_abonos_pedido ON abonos(pedido_id);
CREATE INDEX idx_abonos_fecha  ON abonos(fecha DESC);

-- 3. RLS
ALTER TABLE abonos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Usuarios autenticados pueden ver abonos"
ON abonos FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Usuarios autenticados pueden crear abonos"
ON abonos FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Usuarios autenticados pueden eliminar abonos"
ON abonos FOR DELETE
TO authenticated
USING (true);

-- =============================================
-- RPC: Resumen financiero de un pedido
-- =============================================
CREATE OR REPLACE FUNCTION get_resumen_pagos(p_pedido_id UUID)
RETURNS JSON AS $$
DECLARE
  v_total_pedido    INT;
  v_total_abonado   INT;
  v_saldo           INT;
BEGIN
  -- Obtener total del pedido
  SELECT total_pedido INTO v_total_pedido
  FROM pedidos
  WHERE id = p_pedido_id;

  -- Sumar todos los abonos
  SELECT COALESCE(SUM(valor), 0) INTO v_total_abonado
  FROM abonos
  WHERE pedido_id = p_pedido_id;

  -- Calcular saldo (puede ser negativo si se abonó antes de calcular el total)
  v_saldo := v_total_pedido - v_total_abonado;

  RETURN json_build_object(
    'total_pedido',   v_total_pedido,
    'total_abonado',  v_total_abonado,
    'saldo_pendiente', v_saldo
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- RPC: Agregar abono
-- =============================================
CREATE OR REPLACE FUNCTION add_abono(
  p_pedido_id UUID,
  p_valor     INT,
  p_tipo_pago TEXT,
  p_fecha     DATE DEFAULT CURRENT_DATE,
  p_notas     TEXT DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
  v_abono abonos%ROWTYPE;
BEGIN
  INSERT INTO abonos (pedido_id, valor, tipo_pago, fecha, notas)
  VALUES (p_pedido_id, p_valor, p_tipo_pago, p_fecha, p_notas)
  RETURNING * INTO v_abono;

  RETURN row_to_json(v_abono);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
