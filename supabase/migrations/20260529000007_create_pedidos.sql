-- =============================================
-- MÓDULO PEDIDOS - 18D JOYEROS
-- =============================================

-- 1. Tabla principal de Pedidos
CREATE TABLE pedidos (
  id                      UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  referencia              TEXT NOT NULL UNIQUE,
  fecha_inicio            DATE NOT NULL,
  fecha_fin               DATE NOT NULL,
  titulo                  TEXT NOT NULL,
  descripcion             TEXT,
  talla                   TEXT,
  peso                    NUMERIC(8,3),
  color_id                INT NOT NULL REFERENCES colores_oro(id),
  responsable_id          UUID NOT NULL REFERENCES profiles(id),
  cliente_id              UUID NOT NULL REFERENCES profiles(id),
  tiene_diseno            BOOLEAN NOT NULL DEFAULT false,
  id_diseno               UUID REFERENCES disenos_3d(id) ON DELETE SET NULL,
  peso_final              NUMERIC(8,3) DEFAULT 0,
  precio_gramo            INT DEFAULT 0,
  precio_adicionales      INT DEFAULT 0,
  descripcion_adicionales TEXT,
  total_pedido            INT DEFAULT 0,
  estado                  TEXT NOT NULL DEFAULT 'pendiente_fabricar'
                            CHECK (estado IN ('pendiente_fabricar', 'entregado')),
  imagen                  TEXT,
  created_at              TIMESTAMPTZ DEFAULT NOW(),

  -- fecha_fin debe ser >= fecha_inicio
  CONSTRAINT check_fechas_pedido CHECK (fecha_fin >= fecha_inicio),
  -- Si tiene_diseno = false, id_diseno debe ser NULL
  -- Si tiene_diseno = true, id_diseno debe estar presente
  CONSTRAINT check_diseno_fk CHECK (
    (tiene_diseno = false AND id_diseno IS NULL) OR
    (tiene_diseno = true AND id_diseno IS NOT NULL)
  )
);

-- 2. Función para generar referencia automática COT-###
CREATE OR REPLACE FUNCTION generate_pedido_referencia()
RETURNS TRIGGER AS $$
DECLARE
  next_num INT;
BEGIN
  SELECT COALESCE(
    MAX(CAST(SUBSTRING(referencia FROM 5) AS INT)),
    0
  ) + 1
  INTO next_num
  FROM pedidos;

  NEW.referencia := 'COT-' || LPAD(next_num::TEXT, 3, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Trigger que se ejecuta antes de cada INSERT
CREATE TRIGGER set_pedido_referencia
BEFORE INSERT ON pedidos
FOR EACH ROW
EXECUTE FUNCTION generate_pedido_referencia();

-- 4. Índices para performance
CREATE INDEX idx_pedidos_color ON pedidos(color_id);
CREATE INDEX idx_pedidos_responsable ON pedidos(responsable_id);
CREATE INDEX idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX idx_pedidos_estado ON pedidos(estado);
CREATE INDEX idx_pedidos_diseno ON pedidos(id_diseno);
CREATE INDEX idx_pedidos_created ON pedidos(created_at DESC);

-- 5. RLS Policies
ALTER TABLE pedidos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Usuarios autenticados pueden ver pedidos"
ON pedidos FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Usuarios autenticados pueden crear pedidos"
ON pedidos FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Usuarios autenticados pueden actualizar pedidos"
ON pedidos FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

CREATE POLICY "Usuarios autenticados pueden eliminar pedidos"
ON pedidos FOR DELETE
TO authenticated
USING (true);

-- =============================================
-- RPC: Crear Pedido (con creación atómica de diseño si aplica)
-- =============================================
CREATE OR REPLACE FUNCTION create_pedido_con_diseno(
  p_fecha_inicio      DATE,
  p_fecha_fin         DATE,
  p_titulo            TEXT,
  p_descripcion       TEXT,
  p_talla             TEXT,
  p_peso              NUMERIC,
  p_color_id          INT,
  p_responsable_id    UUID,
  p_cliente_id        UUID,
  p_tiene_diseno      BOOLEAN,
  p_peso_final        NUMERIC,
  p_precio_gramo      INT,
  p_precio_adicionales INT,
  p_descripcion_adicionales TEXT,
  p_total_pedido      INT,
  p_estado            TEXT,
  p_imagen            TEXT
) RETURNS JSON AS $$
DECLARE
  v_diseno_id UUID := NULL;
  v_pedido    pedidos%ROWTYPE;
BEGIN
  -- Si tiene_diseno = true, primero crear el diseño
  IF p_tiene_diseno THEN
    INSERT INTO disenos_3d (
      referencia,
      fecha_inicio,
      fecha_fin,
      titulo,
      descripcion,
      talla,
      peso,
      color_id,
      responsable_id,
      cliente_id,
      precio_diseno,
      precio_impresion,
      imagen
    ) VALUES (
      'TEMP',  -- El trigger de disenos_3d generará DIS-###
      p_fecha_inicio,
      p_fecha_fin,
      p_titulo,
      p_descripcion,
      p_talla,
      p_peso,
      p_color_id,
      p_responsable_id,
      p_cliente_id,
      0,
      0,
      p_imagen  -- Misma referencia de imagen
    )
    RETURNING id INTO v_diseno_id;
  END IF;

  -- Insertar el pedido
  INSERT INTO pedidos (
    referencia,
    fecha_inicio,
    fecha_fin,
    titulo,
    descripcion,
    talla,
    peso,
    color_id,
    responsable_id,
    cliente_id,
    tiene_diseno,
    id_diseno,
    peso_final,
    precio_gramo,
    precio_adicionales,
    descripcion_adicionales,
    total_pedido,
    estado,
    imagen
  ) VALUES (
    'TEMP',  -- El trigger de pedidos generará COT-###
    p_fecha_inicio,
    p_fecha_fin,
    p_titulo,
    p_descripcion,
    p_talla,
    p_peso,
    p_color_id,
    p_responsable_id,
    p_cliente_id,
    p_tiene_diseno,
    v_diseno_id,
    p_peso_final,
    p_precio_gramo,
    p_precio_adicionales,
    p_descripcion_adicionales,
    p_total_pedido,
    p_estado,
    p_imagen
  )
  RETURNING * INTO v_pedido;

  RETURN row_to_json(v_pedido);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- RPC: Actualizar Pedido
-- =============================================
CREATE OR REPLACE FUNCTION update_pedido(
  p_id                    UUID,
  p_fecha_inicio          DATE,
  p_fecha_fin             DATE,
  p_titulo                TEXT,
  p_descripcion           TEXT,
  p_talla                 TEXT,
  p_peso                  NUMERIC,
  p_color_id              INT,
  p_responsable_id        UUID,
  p_cliente_id            UUID,
  p_tiene_diseno          BOOLEAN,
  p_id_diseno             UUID,
  p_peso_final            NUMERIC,
  p_precio_gramo          INT,
  p_precio_adicionales    INT,
  p_descripcion_adicionales TEXT,
  p_total_pedido          INT,
  p_estado                TEXT,
  p_imagen                TEXT
) RETURNS void AS $$
BEGIN
  UPDATE pedidos
  SET
    fecha_inicio          = p_fecha_inicio,
    fecha_fin             = p_fecha_fin,
    titulo                = p_titulo,
    descripcion           = p_descripcion,
    talla                 = p_talla,
    peso                  = p_peso,
    color_id              = p_color_id,
    responsable_id        = p_responsable_id,
    cliente_id            = p_cliente_id,
    tiene_diseno          = p_tiene_diseno,
    id_diseno             = p_id_diseno,
    peso_final            = p_peso_final,
    precio_gramo          = p_precio_gramo,
    precio_adicionales    = p_precio_adicionales,
    descripcion_adicionales = p_descripcion_adicionales,
    total_pedido          = p_total_pedido,
    estado                = p_estado,
    imagen                = p_imagen
  WHERE id = p_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
