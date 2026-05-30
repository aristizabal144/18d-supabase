-- =============================================
-- MÓDULO DISEÑOS 3D - 18D JOYEROS
-- =============================================

-- 1. Tabla de Colores de Oro (compartida con cotizaciones)
CREATE TABLE IF NOT EXISTS colores_oro (
  id     SERIAL PRIMARY KEY,
  nombre TEXT NOT NULL UNIQUE
    CHECK (nombre IN ('Amarillo', 'Blanco', 'Rosado', 'Multicolor'))
);

INSERT INTO colores_oro (nombre)
VALUES ('Amarillo'), ('Blanco'), ('Rosado'), ('Multicolor')
ON CONFLICT (nombre) DO NOTHING;

-- 2. Tabla principal de Diseños 3D
CREATE TABLE disenos_3d (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  referencia        TEXT NOT NULL UNIQUE,
  fecha_inicio      DATE NOT NULL,
  fecha_fin         DATE NOT NULL,
  titulo            TEXT NOT NULL,
  descripcion       TEXT,
  talla             TEXT,
  peso              NUMERIC(8,3),
  color_id          INT NOT NULL REFERENCES colores_oro(id),
  responsable_id    UUID NOT NULL REFERENCES profiles(id),
  cliente_id        UUID NOT NULL REFERENCES profiles(id),
  precio_diseno     INT NOT NULL DEFAULT 0,
  precio_impresion  INT NOT NULL DEFAULT 0,
  imagen            TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW(),

  -- Constraint: fecha_fin debe ser >= fecha_inicio
  CONSTRAINT check_fechas CHECK (fecha_fin >= fecha_inicio)
);

-- 3. Función para generar referencia automática DIS-###
CREATE OR REPLACE FUNCTION generate_diseno_referencia()
RETURNS TRIGGER AS $$
DECLARE
  next_num INT;
BEGIN
  SELECT COALESCE(
    MAX(CAST(SUBSTRING(referencia FROM 5) AS INT)),
    0
  ) + 1
  INTO next_num
  FROM disenos_3d;

  NEW.referencia := 'DIS-' || LPAD(next_num::TEXT, 3, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Trigger que se ejecuta antes de cada INSERT
CREATE TRIGGER set_diseno_referencia
BEFORE INSERT ON disenos_3d
FOR EACH ROW
EXECUTE FUNCTION generate_diseno_referencia();

-- 5. Índices para performance
CREATE INDEX idx_disenos_color ON disenos_3d(color_id);
CREATE INDEX idx_disenos_responsable ON disenos_3d(responsable_id);
CREATE INDEX idx_disenos_cliente ON disenos_3d(cliente_id);
CREATE INDEX idx_disenos_created ON disenos_3d(created_at DESC);

-- 6. RLS Policies
ALTER TABLE disenos_3d ENABLE ROW LEVEL SECURITY;

-- SELECT: usuarios autenticados pueden ver todos
CREATE POLICY "Usuarios autenticados pueden ver diseños"
ON disenos_3d FOR SELECT
TO authenticated
USING (true);

-- INSERT: usuarios autenticados pueden crear
CREATE POLICY "Usuarios autenticados pueden crear diseños"
ON disenos_3d FOR INSERT
TO authenticated
WITH CHECK (true);

-- UPDATE: usuarios autenticados pueden actualizar
CREATE POLICY "Usuarios autenticados pueden actualizar diseños"
ON disenos_3d FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

-- DELETE: usuarios autenticados pueden eliminar
CREATE POLICY "Usuarios autenticados pueden eliminar diseños"
ON disenos_3d FOR DELETE
TO authenticated
USING (true);

-- RLS para colores_oro (lectura pública)
ALTER TABLE colores_oro ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Lectura pública de colores"
ON colores_oro FOR SELECT
TO authenticated
USING (true);

-- =============================================
-- STORAGE BUCKET: disenos-imagenes
-- =============================================

INSERT INTO storage.buckets (id, name, public) 
VALUES ('disenos-imagenes', 'disenos-imagenes', true)
ON CONFLICT (id) DO NOTHING;

-- Policy: cualquier autenticado puede subir archivos
CREATE POLICY "Usuarios autenticados pueden subir imágenes de diseños"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'disenos-imagenes');

-- Policy: cualquier autenticado puede actualizar sus archivos
CREATE POLICY "Usuarios autenticados pueden actualizar imágenes de diseños"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'disenos-imagenes');

-- Policy: cualquier autenticado puede eliminar archivos
CREATE POLICY "Usuarios autenticados pueden eliminar imágenes de diseños"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'disenos-imagenes');

-- Policy: acceso público de lectura (el bucket es público)
CREATE POLICY "Lectura pública de imágenes de diseños"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'disenos-imagenes');
