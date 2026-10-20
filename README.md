# Monse Nails Studio: web + Supabase

## Qué hay en esta carpeta

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La web completa: la página pública, la reserva y el panel de María (`/#panel`). |
| `fotos/` | Las fotos de referencia de los servicios y la foto de María. |
| `supabase/schema.sql` | La base de datos: tablas, seguridad, reglas de reserva y fidelidad, y fotos. |
| `supabase/migraciones/002_calendario_y_avisos.sql` | Actualización para quien ya corrió `schema.sql`: calendario en vivo y revisión de permisos. |
| `supabase/migraciones/003_jornada_laboral.sql` | Actualización para quien ya corrió `schema.sql`: jornada laboral editable desde el panel. |
| `supabase/functions/notificar-reserva/` | Avisos automáticos: correo a la clienta y WhatsApp a María. |
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
- María entra a `tu-link/#panel` con su correo y contraseña. Lo primero que ve es **su calendario de la semana**. Si toca un bloque, ve todos los datos de la clienta. Puede arrastrar el bloque a otro día y hora (en el celular lo hace desde "Mover a otro día u hora") o cancelarlo para liberarlo. En las otras pestañas ve los ingresos, el servicio que más y menos plata deja, las reservas, las clientas con sus sellos y los servicios. También puede marcar las citas como completadas o canceladas, cambiar precios y fotos, y agregar o quitar servicios.
- En la pestaña **Jornada laboral** María elige qué días atiende (incluido el domingo), desde y hasta qué hora, cuánto dura cada bloque (1, 2 o 3 horas) y qué bloques se pueden reservar (por ejemplo, deja libre la hora de almuerzo). Al guardar, la web y el calendario cambian al tiro. Las horas ya reservadas no se borran: si quedan fuera de la nueva jornada, el panel lo avisa para que las mueva o cancele.

## Reglas que ya están en la base de datos
- Al principio hay bloques a las 10, 12, 14, 16 y 18 h, de lunes a sábado. María los cambia desde **Jornada laboral** y la base de datos solo acepta reservas en los días y bloques que ella dejó activos (tabla `ajustes`). Se puede reservar desde mañana hasta 60 días adelante.
- Un bloque no se puede reservar dos veces. Si dos personas reservan a la vez, la segunda recibe un aviso para elegir otro.
- Cada clienta se reconoce por su correo o su teléfono. Su 6.º servicio (y el 12.º, el 18.º…) queda marcado como **gratis** y no suma a los ingresos.
- Las visitas no ven datos de otras clientas. Solo pueden ver los servicios activos y qué bloques están ocupados.

## Si una reserva no aparece en el panel
1. **¿Ya corriste las actualizaciones 002 y 003?** Si ya tenías la base de datos creada, pega y corre `supabase/migraciones/002_calendario_y_avisos.sql` y después `003_jornada_laboral.sql` en SQL Editor. La 002 muestra al final qué correos pueden entrar al panel.
2. **¿El correo de María está autorizado?** El panel ahora lo revisa. Si dice *"Este correo no está autorizado"*, te muestra la línea exacta que hay que correr en SQL Editor. Este suele ser el problema: el `schema.sql` traía `maria@ejemplo.cl` como ejemplo.
3. **¿La web está en modo demo?** Si arriba dice "Modo demo", el hosting no tiene las variables `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Agrégalas y vuelve a publicar. En modo demo, las reservas solo quedan en el navegador de quien reservó.

## Avisos automáticos (correo a la clienta y WhatsApp a María)
Cuando alguien reserva, la clienta recibe un correo de confirmación y a María le llega un WhatsApp con los datos. Si María mueve o cancela una hora, la clienta también recibe un correo. Las dos herramientas son gratis.

### a) Correo con Brevo
1. Crea una cuenta en [brevo.com](https://www.brevo.com). El plan gratis permite 300 correos al día.
2. En **Senders, Domains & Dedicated IPs → Senders**, agrega el correo que va a aparecer como remitente (por ejemplo el Gmail del studio) y confírmalo desde ese correo.
3. En **SMTP & API → API Keys**, crea una llave y cópiala.

> ¿Tienen dominio propio (por ejemplo monsenails.cl)? Pueden usar [Resend](https://resend.com) en vez de Brevo. En ese caso usa `RESEND_API_KEY` en lugar de `BREVO_API_KEY`.

### b) WhatsApp a María con CallMeBot
1. Desde el WhatsApp de María, sigue las instrucciones de [callmebot.com → WhatsApp API](https://www.callmebot.com/blog/free-api-whatsapp-messages/). Hay que agregar el número de CallMeBot a los contactos y mandarle el mensaje de activación.
2. CallMeBot le responde a María con su `apikey`.

> CallMeBot sirve para mandarse avisos a uno mismo, que es justo este caso. Si más adelante quieren algo más formal, la alternativa es Twilio o WhatsApp Cloud API (de pago).

### c) Crear la función en Supabase
1. Ve a **Edge Functions → Deploy a new function → Via Editor**. Ponle de nombre `notificar-reserva`, pega el contenido de `supabase/functions/notificar-reserva/index.ts` y toca **Deploy**.
2. En **Edge Functions → Secrets**, agrega:
   - `BREVO_API_KEY`: la llave de Brevo
   - `EMAIL_FROM`: el remitente que confirmaste en Brevo
   - `CALLMEBOT_APIKEY`: la apikey que recibió María
   - `MARIA_WHATSAPP`: el número que activó CallMeBot, por ejemplo `+56926108745`. CallMeBot solo le escribe al número dueño de la apikey. Mientras se prueba, el aviso va por defecto al teléfono de Gabo (`+56987380493`), así que Gabo debe activar CallMeBot desde su WhatsApp.
   - `AVISO_CORREO` (opcional): un correo del studio que también recibe cada reserva nueva.
3. En **Database → Webhooks → Create a new hook**:
   - Nombre: `avisos-reservas`. Tabla: `reservas`. Eventos: **Insert** y **Update**.
   - Tipo: **Supabase Edge Functions**, función `notificar-reserva`, método POST.
   - Deja activada la opción de agregar el header de autorización (Authorization con la service key).
4. En `index.html`, cambia `avisosAutomaticos: false` por `true`. Cuando terminen las pruebas, cambia también `avisoWhatsapp` al número de María (`56926108745`). Así la pantalla de confirmación le dice a la clienta que le llegó un correo.
5. Haz una reserva de prueba. Si algo falla, **Edge Functions → notificar-reserva → Logs** muestra el error exacto (por ejemplo, una llave mal copiada).
