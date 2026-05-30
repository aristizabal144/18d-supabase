-- =============================================
-- RPC FUNCTION PARA ACTUALIZAR DISEÑO 3D (Bypass PATCH CORS)
-- =============================================

CREATE OR REPLACE FUNCTION update_diseno_3d(
    p_id uuid,
    p_fecha_inicio date,
    p_fecha_fin date,
    p_titulo text,
    p_descripcion text,
    p_talla text,
    p_peso numeric,
    p_color_id int,
    p_responsable_id uuid,
    p_cliente_id uuid,
    p_precio_diseno int,
    p_precio_impresion int,
    p_imagen text
) RETURNS void AS $$
BEGIN
    UPDATE disenos_3d
    SET 
        fecha_inicio = p_fecha_inicio,
        fecha_fin = p_fecha_fin,
        titulo = p_titulo,
        descripcion = p_descripcion,
        talla = p_talla,
        peso = p_peso,
        color_id = p_color_id,
        responsable_id = p_responsable_id,
        cliente_id = p_cliente_id,
        precio_diseno = p_precio_diseno,
        precio_impresion = p_precio_impresion,
        imagen = p_imagen
    WHERE id = p_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
