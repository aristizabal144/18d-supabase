-- ============================================================
-- MIGRACIÓN: Módulo Impresiones 3D — Facturación de Moldes
-- 18D Joyeros - Sistema de Control
-- Fecha: 2026-08-24
-- ============================================================

-- 1. Tabla de cabeceras de factura de impresión 3D
CREATE TABLE IF NOT EXISTS facturas_3d (
  id          uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  numero      serial      UNIQUE NOT NULL,
  fecha       date        NOT NULL,
  cliente_id  uuid        REFERENCES profiles(id) ON DELETE SET NULL,
  estado      text        NOT NULL DEFAULT 'pendiente'
                          CHECK (estado IN ('pendiente', 'pagado')),
  total       numeric     NOT NULL DEFAULT 0,
  peso_total  numeric     NOT NULL DEFAULT 0,
  notas       text,
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now()
);

-- 2. Tabla de ítems (líneas) de cada factura
CREATE TABLE IF NOT EXISTS facturas_3d_items (
  id            uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  factura_id    uuid        NOT NULL REFERENCES facturas_3d(id) ON DELETE CASCADE,
  nombre_molde  text        NOT NULL,
  precio        numeric     NOT NULL DEFAULT 55000,
  peso          numeric     NOT NULL DEFAULT 0,
  created_at    timestamptz DEFAULT now()
);

-- 3. Índices para búsquedas frecuentes
CREATE INDEX IF NOT EXISTS idx_facturas_3d_fecha      ON facturas_3d(fecha);
CREATE INDEX IF NOT EXISTS idx_facturas_3d_cliente_id ON facturas_3d(cliente_id);
CREATE INDEX IF NOT EXISTS idx_facturas_3d_estado     ON facturas_3d(estado);
CREATE INDEX IF NOT EXISTS idx_facturas_3d_items_fk   ON facturas_3d_items(factura_id);

-- 4. RLS (Row Level Security)
ALTER TABLE facturas_3d       ENABLE ROW LEVEL SECURITY;
ALTER TABLE facturas_3d_items ENABLE ROW LEVEL SECURITY;

-- Política: usuarios autenticados pueden gestionar todo
CREATE POLICY "Authenticated users can manage facturas_3d"
  ON facturas_3d FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users can manage facturas_3d_items"
  ON facturas_3d_items FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- ============================================================
-- FIN DE MIGRACIÓN
-- ============================================================
