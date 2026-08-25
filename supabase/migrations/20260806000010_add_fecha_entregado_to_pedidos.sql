-- =============================================
-- AGREGAR FECHA DE ENTREGADO EN PEDIDOS - 18D JOYEROS
-- =============================================

-- 1. Agregar columna fecha_entregado a la tabla pedidos si no existe
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name='pedidos' AND column_name='fecha_entregado'
    ) THEN
        ALTER TABLE pedidos ADD COLUMN fecha_entregado DATE DEFAULT NULL;
    END IF;
END $$;

-- 2. Función Trigger para actualizar fecha_entregado automáticamente según el estado
CREATE OR REPLACE FUNCTION handle_pedido_fecha_entregado()
RETURNS TRIGGER AS $$
BEGIN
  -- Si pasa a entregado o se inserta como entregado
  IF NEW.estado = 'entregado' THEN
    IF OLD IS NULL OR OLD.estado IS DISTINCT FROM 'entregado' OR NEW.fecha_entregado IS NULL THEN
      NEW.fecha_entregado := COALESCE(NEW.fecha_entregado, CURRENT_DATE);
    END IF;
  -- Si pasa a pendiente_fabricar
  ELSIF NEW.estado = 'pendiente_fabricar' THEN
    NEW.fecha_entregado := NULL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Crear el Trigger si no existe
DROP TRIGGER IF EXISTS trg_pedido_fecha_entregado ON pedidos;
CREATE TRIGGER trg_pedido_fecha_entregado
BEFORE INSERT OR UPDATE OF estado, fecha_entregado ON pedidos
FOR EACH ROW
EXECUTE FUNCTION handle_pedido_fecha_entregado();

-- 4. Actualizar pedidos existentes en entregado si no tienen fecha
UPDATE pedidos SET fecha_entregado = CURRENT_DATE WHERE estado = 'entregado' AND fecha_entregado IS NULL;

-- 5. Actualizar RPC update_pedido para aceptar opcionalmente p_fecha_entregado
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
  p_imagen                TEXT,
  p_fecha_entregado       DATE DEFAULT NULL
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
    imagen                = p_imagen,
    fecha_entregado       = CASE 
                              WHEN p_estado = 'pendiente_fabricar' THEN NULL
                              WHEN p_estado = 'entregado' THEN COALESCE(p_fecha_entregado, fecha_entregado, CURRENT_DATE)
                              ELSE fecha_entregado
                            END
  WHERE id = p_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
