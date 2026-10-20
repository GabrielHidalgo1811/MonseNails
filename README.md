# Monse Nails Studio: web + Supabase

## Qué hay en esta carpeta

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La web completa: la página pública, la reserva y el panel de María (`/#panel`). |
| `fotos/` | Las fotos de referencia de los servicios y la foto de María. |
| `supabase/schema.sql` | La base de datos: tablas, seguridad, reglas de reserva y fidelidad, y fotos. |
| `build.mjs` | Arma la carpeta `dist/` para publicar y pone ahí las llaves de Supabase. |
| `.env.example` | Modelo del archivo `.env` donde van las llaves. El `.env` real no se sube a GitHub. |
| `netlify.toml` / `vercel.json` | Configuración para publicar en Netlify o Vercel. |

Sin llaves, la web funciona en **modo demo** con datos de ejemplo.

## Paso a paso

### 1. Crear la base de datos
1. Crea un proyecto en [supabase.com](https://supabase.com). La región más cercana es São Paulo.
2. Abre **SQL Editor → New query**.
3. Abre `supabase/schema.sql` y busca la sección 6. Cambia `maria@ejemplo.cl` por el correo real de María.
4. Pega todo el archivo y toca **Run**. Esto crea las tablas, las reglas, el espacio para fotos (bucket `fotos`) y los 5 servicios.

### 2. Crear el usuario de María
1. Ve a **Authentication → Users → Add user → Create new user**. Usa el mismo correo del paso anterior, ponle una contraseña y marca **Auto Confirm User**.
2. Ve a **Authentication → Sign In / Providers** y desactiva **Allow new users to sign up**. Así nadie más puede crearse una cuenta.

### 3. Llaves (en `.env`, nunca en GitHub)
1. Copia `.env.example` como `.env` y completa los datos de **Project Settings → API**:
   ```
   NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
   NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```
2. `.env` está en `.gitignore`, así que nunca se sube al repositorio.
3. Usa solo la llave **publishable** (o la anon). La **secret** (`sb_secret_…`) jamás va en la web, y `build.mjs` se niega a usarla.

> La llave publishable está hecha para ir en el navegador. Quien visite la web puede verla, y eso es normal: las reglas del SQL deciden qué puede hacer cada persona. Con esto queda fuera de GitHub, que es lo que importa.

### 4. Publicar la web
**Netlify o Vercel (recomendado):**
1. Importa el repositorio de GitHub. `netlify.toml` y `vercel.json` ya dicen que hay que correr `node build.mjs` y publicar la carpeta `dist`.
2. En el panel del hosting, ve a **Environment variables** y agrega `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` con los mismos valores del `.env`.
3. Haz un deploy. Cada vez que subas cambios a GitHub, la web se actualiza sola.

**Para probarla en tu computador:** con el `.env` listo, corre `node build.mjs` y luego `npx serve dist`. Después abre el link que aparece.

### 5. Usarla
- Las clientas entran al link, eligen un servicio, un día y un bloque de 2 horas, y dejan nombre, apellido, correo y teléfono.
- La reserva queda guardada en Supabase, y aparece un botón para mandarle el aviso a María por WhatsApp (+56 9 2610 8745).
- María entra a `tu-link/#panel` con su correo y contraseña. Ahí ve los ingresos, el servicio que más y menos plata deja, las reservas, las clientas con sus sellos y los servicios. También puede marcar las citas como completadas o canceladas, cambiar precios y fotos, y agregar o quitar servicios.

## Reglas que ya están en la base de datos
- Hay bloques a las 10, 12, 14, 16 y 18 h, de lunes a sábado, para reservar desde mañana hasta 60 días adelante. Para cambiarlos, edita `STUDIO.bloques` en `index.html` y los números `(10, 12, 14, 16, 18)` en `schema.sql`.
- Un bloque no se puede reservar dos veces. Si dos personas reservan a la vez, la segunda recibe un aviso para elegir otro.
- Cada clienta se reconoce por su correo o su teléfono. Su 6.º servicio (y el 12.º, el 18.º…) queda marcado como **gratis** y no suma a los ingresos.
- Las visitas no ven datos de otras clientas. Solo pueden ver los servicios activos y qué bloques están ocupados.

## Siguiente paso opcional
Para que el aviso le llegue a María por WhatsApp de forma automática, sin que la clienta toque el botón, hace falta un servicio de WhatsApp (por ejemplo WhatsApp Cloud API o Twilio) conectado con una Edge Function de Supabase.
