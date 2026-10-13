-- =============================================================================
-- Migración: 015 - Configuración del Negocio (identidad, marca y formato)
-- Descripción: Crea la tabla de configuración de fila única con los datos de
--              identidad del negocio que usan la interfaz y los documentos
--              impresos (facturas, comprobantes, reportes).
--              Modelo de despliegue: UNA instalación por cliente (cada negocio
--              tiene su propio proyecto Supabase), por eso no hay multi-tenant.
--              Solo el rol 'admin' puede modificar la configuración.
--              Incluye el bucket público 'branding' para los logos.
-- Fecha: 2026-10-12
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLA: public.configuracion_negocio (fila única, id = 1)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.configuracion_negocio (
    id                      SMALLINT    PRIMARY KEY DEFAULT 1 CHECK (id = 1),

    -- Identidad
    nombre_comercial        TEXT        NOT NULL CHECK (CHAR_LENGTH(TRIM(nombre_comercial)) > 0),
    razon_social            TEXT,
    nit                     TEXT,
    eslogan                 TEXT,
    direccion               TEXT,
    ciudad                  TEXT,
    pais                    TEXT,
    telefono                TEXT,
    correo                  TEXT,
    sitio_web               TEXT,
    instagram               TEXT,
    facebook                TEXT,
    whatsapp                TEXT,

    -- Logo (NULL => la app usa el logo incluido por defecto)
    logo_url                TEXT,
    logo_claro_url          TEXT,

    -- Textos de documentos
    terminos_pedido         TEXT,
    terminos_impresion3d    TEXT,
    terminos_cartera        TEXT,
    terminos_vales          TEXT,
    texto_firma_autorizada  TEXT,

    -- Marca
    color_primario          TEXT        NOT NULL DEFAULT '#C9A84C'
                                        CONSTRAINT configuracion_negocio_color_primario_hex
                                        CHECK (color_primario ~ '^#[0-9A-Fa-f]{6}$'),

    -- Formato regional
    moneda                  TEXT        NOT NULL DEFAULT 'COP' CHECK (moneda ~ '^[A-Z]{3}$'),
    locale                  TEXT        NOT NULL DEFAULT 'es-CO',
    decimales_moneda        SMALLINT    NOT NULL DEFAULT 0 CHECK (decimales_moneda BETWEEN 0 AND 4),

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.configuracion_negocio                        IS 'Configuración de identidad del negocio (fila única, id = 1). Una instalación por cliente.';
COMMENT ON COLUMN public.configuracion_negocio.id                     IS 'Siempre 1. Garantiza que solo exista una fila de configuración.';
COMMENT ON COLUMN public.configuracion_negocio.nombre_comercial       IS 'Nombre comercial que se muestra en la interfaz, el login y los documentos.';
COMMENT ON COLUMN public.configuracion_negocio.razon_social           IS 'Razón social legal que aparece en facturas y comprobantes.';
COMMENT ON COLUMN public.configuracion_negocio.nit                    IS 'Identificación tributaria (NIT, RUC, RFC, etc.).';
COMMENT ON COLUMN public.configuracion_negocio.eslogan                IS 'Eslogan o descripción corta del negocio para el encabezado de documentos.';
COMMENT ON COLUMN public.configuracion_negocio.direccion              IS 'Dirección física del negocio.';
COMMENT ON COLUMN public.configuracion_negocio.ciudad                 IS 'Ciudad del negocio.';
COMMENT ON COLUMN public.configuracion_negocio.pais                   IS 'País del negocio.';
COMMENT ON COLUMN public.configuracion_negocio.telefono               IS 'Teléfono de contacto que aparece en los documentos.';
COMMENT ON COLUMN public.configuracion_negocio.correo                 IS 'Correo de contacto que aparece en los documentos.';
COMMENT ON COLUMN public.configuracion_negocio.sitio_web              IS 'Sitio web del negocio (opcional).';
COMMENT ON COLUMN public.configuracion_negocio.instagram              IS 'Usuario o enlace de Instagram (opcional).';
COMMENT ON COLUMN public.configuracion_negocio.facebook               IS 'Usuario o enlace de Facebook (opcional).';
COMMENT ON COLUMN public.configuracion_negocio.whatsapp               IS 'Número de WhatsApp (opcional).';
COMMENT ON COLUMN public.configuracion_negocio.logo_url               IS 'URL pública del logo principal (fondos claros). NULL usa el logo por defecto.';
COMMENT ON COLUMN public.configuracion_negocio.logo_claro_url         IS 'URL pública del logo para fondos oscuros. NULL usa el logo principal.';
COMMENT ON COLUMN public.configuracion_negocio.terminos_pedido        IS 'Términos y garantía impresos en el comprobante de pedido.';
COMMENT ON COLUMN public.configuracion_negocio.terminos_impresion3d   IS 'Términos y garantía impresos en la factura de impresión 3D.';
COMMENT ON COLUMN public.configuracion_negocio.terminos_cartera       IS 'Condiciones de cobro del estado de cuenta de cartera (una por línea).';
COMMENT ON COLUMN public.configuracion_negocio.terminos_vales         IS 'Condiciones impresas en el comprobante de vale (opcional).';
COMMENT ON COLUMN public.configuracion_negocio.texto_firma_autorizada IS 'Texto bajo la firma autorizada de los documentos.';
COMMENT ON COLUMN public.configuracion_negocio.color_primario         IS 'Color principal de la marca en formato hexadecimal (#RRGGBB).';
COMMENT ON COLUMN public.configuracion_negocio.moneda                 IS 'Código ISO 4217 de la moneda (COP, USD, MXN, ...).';
COMMENT ON COLUMN public.configuracion_negocio.locale                 IS 'Locale BCP 47 para formatear números y fechas (es-CO, es-MX, en-US, ...).';
COMMENT ON COLUMN public.configuracion_negocio.decimales_moneda       IS 'Cantidad de decimales al mostrar valores monetarios.';
COMMENT ON COLUMN public.configuracion_negocio.created_at             IS 'Fecha y hora de creación del registro.';
COMMENT ON COLUMN public.configuracion_negocio.updated_at             IS 'Fecha y hora de la última actualización.';

-- -----------------------------------------------------------------------------
-- 2. TRIGGER: Actualizar updated_at automáticamente
--    Reutiliza la función public.set_updated_at() de la migración 001.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_configuracion_negocio_updated_at ON public.configuracion_negocio;

CREATE TRIGGER trg_configuracion_negocio_updated_at
    BEFORE UPDATE ON public.configuracion_negocio
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- 3. DATOS SEMILLA (Seed): valores actuales de 18D JOYEROS
--    En una instalación nueva el administrador los reemplaza desde la página
--    Configuración. ON CONFLICT evita sobrescribir una configuración existente.
-- -----------------------------------------------------------------------------
INSERT INTO public.configuracion_negocio (
    id,
    nombre_comercial,
    razon_social,
    nit,
    eslogan,
    ciudad,
    pais,
    telefono,
    correo,
    terminos_pedido,
    terminos_impresion3d,
    terminos_cartera,
    terminos_vales,
    texto_firma_autorizada,
    color_primario,
    moneda,
    locale,
    decimales_moneda
)
VALUES (
    1,
    '18D Joyeros',
    '18D Joyeros S.A.S',
    '901.482.930-1',
    'Joyería Fina & Diseños Personalizados 18k',
    'Medellín',
    'Colombia',
    '+57 (300) 18D-JOYA',
    'info@18djoyeros.com',
    'Garantía de por vida en la ley del metal (Oro 18k). No cubre pérdida de piedras por uso inadecuado o golpes. Conserve este comprobante para el retiro de su joya.',
    'Garantía de calidad en la definición y cura de resina de impresión 3D para alta joyería. Verifique sus moldes al momento de la entrega. Conserve este comprobante.',
    E'Garantía de por vida en la autenticidad del oro 18k.\nEl saldo pendiente debe cancelarse al momento del retiro.',
    NULL,
    '18D Joyeros S.A.S',
    '#C9A84C',
    'COP',
    'es-CO',
    0
)
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS)
--    - Lectura pública (anon + authenticated): el login necesita nombre y logo
--      antes de iniciar sesión. No contiene datos sensibles.
--    - UPDATE solo para administradores (public.is_admin(), migración 004).
--    - Sin políticas de INSERT/DELETE para clientes: la fila se crea en la
--      semilla y no debe eliminarse. service_role conserva acceso total.
-- -----------------------------------------------------------------------------
ALTER TABLE public.configuracion_negocio ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "configuracion_negocio_select_all"     ON public.configuracion_negocio;
DROP POLICY IF EXISTS "configuracion_negocio_update_admin"   ON public.configuracion_negocio;
DROP POLICY IF EXISTS "configuracion_negocio_all_service"    ON public.configuracion_negocio;

CREATE POLICY "configuracion_negocio_select_all"
    ON public.configuracion_negocio
    FOR SELECT
    TO anon, authenticated
    USING (true);

CREATE POLICY "configuracion_negocio_update_admin"
    ON public.configuracion_negocio
    FOR UPDATE
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

CREATE POLICY "configuracion_negocio_all_service"
    ON public.configuracion_negocio
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- 5. STORAGE: Bucket público 'branding' para logos
--    Lectura pública (los logos se muestran en el login y en documentos).
--    Escritura solo para administradores autenticados.
--    SVG se excluye a propósito: un SVG servido públicamente puede contener
--    scripts. Límite de 2 MB por archivo.
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'branding',
    'branding',
    true,
    2097152,
    ARRAY['image/png', 'image/jpeg', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "branding_select_public" ON storage.objects;
DROP POLICY IF EXISTS "branding_insert_admin"  ON storage.objects;
DROP POLICY IF EXISTS "branding_update_admin"  ON storage.objects;
DROP POLICY IF EXISTS "branding_delete_admin"  ON storage.objects;

CREATE POLICY "branding_select_public"
    ON storage.objects
    FOR SELECT
    TO public
    USING (bucket_id = 'branding');

CREATE POLICY "branding_insert_admin"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (bucket_id = 'branding' AND public.is_admin());

CREATE POLICY "branding_update_admin"
    ON storage.objects
    FOR UPDATE
    TO authenticated
    USING (bucket_id = 'branding' AND public.is_admin())
    WITH CHECK (bucket_id = 'branding' AND public.is_admin());

CREATE POLICY "branding_delete_admin"
    ON storage.objects
    FOR DELETE
    TO authenticated
    USING (bucket_id = 'branding' AND public.is_admin());

-- =============================================================================
-- FIN DE MIGRACIÓN
-- =============================================================================
