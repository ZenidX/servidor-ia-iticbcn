# Servidor de IA del ITICBCN: propuesta de arquitectura

*Borrador para el equipo docente · Xavi Lara, Coordinador DUAL & I+D+i · octubre 2026*

## 1. Para qué es el servidor

El centro tiene un servidor con dos GPUs profesionales. Proponemos que sirva para tres cosas, por este orden:

1. **Servicio de LLM al centro.** Un chat y una API de modelos de lenguaje para las actividades de clase, que pueda usar el profesorado y el alumnado sin depender de servicios externos ni de cuentas personales.
2. **Alojar nuestras aplicaciones.** Por ejemplo CoorDUAL, la gestión de la FP Dual, y las que vengan. Los datos personales del alumnado se quedan dentro del centro.
3. **I+D+i.** Modelos de vídeo y de imagen para contenido propio del ITIC (aprobado), y entrenamiento o *fine-tuning* en proyectos de clase.

**Principio rector:** nadie se conecta al sistema operativo, salvo para montar y configurar servicios. Profesorado y alumnado usan el servidor **solo por web y por API**.

## 2. El hardware que tenemos

| Componente | Detalle |
|---|---|
| Equipo | HP Z4 G5 (estación de trabajo) |
| CPU | Intel Xeon w5-2465X, 16 núcleos / 32 hilos |
| RAM | 128 GB (4 × 32 GB; quedan 4 ranuras libres) |
| GPU | **2 × NVIDIA RTX 6000 Ada, 48 GB cada una (96 GB en total)** |
| Disco | 1 × NVMe de 2 TB |

> Las GPUs son **Ada Lovelace de 48 GB**, no Blackwell de 96 GB cada una como pensábamos. Son igualmente muy capaces: soportan FP8 y caben modelos de 30-70 B parámetros (ver §5).

## 3. Cómo está montado ahora

- **Windows 11 Pro de escritorio** como sistema base, con Ubuntu dentro de WSL.
- **Una cuenta de administrador compartida**, por la que entra quien necesita algo.
- **Ollama duplicado:** uno en Windows y otro en WSL, que se disputan el mismo puerto y tienen modelos distintos.
- **Open WebUI** (el chat) lanzado a mano desde una caché temporal. Si se reinicia el equipo, no vuelve solo.
- **Proyectos de compañeros** en carpetas dentro del Ubuntu de WSL.
- **Ya hecho en las últimas semanas:**
  - Acceso remoto de administración por un túnel cifrado de Cloudflare: SSH solo con clave y ningún puerto abierto a internet.
  - ComfyUI para el I+D+i de vídeo, como servicio y en la GPU 1.
  - CoorDUAL en contenedores Docker, con su base de datos y su repositorio git en el propio servidor.

### Problemas de este montaje

- **Fragilidad.** Los servicios dependen de que haya una sesión de Windows abierta. Un reinicio por actualizaciones deja el centro sin chat.
- **No escala a una clase.** Ollama atiende bien a una persona. Con 25-30 alumnos lanzando peticiones a la vez, las respuestas se encolan.
- **Sin control de uso.** No hay claves por grupo, ni cuotas, ni registro de quién usa qué.
- **Seguridad.**
  - Una cuenta compartida con contraseña débil da acceso total.
  - El escritorio invita a "entrar a mirar".
- **Sin copias de seguridad.** Hay un único disco. Si falla, se pierde todo: chats, modelos, la base de datos de CoorDUAL.
- **Sin monitorización.** Nadie se entera si algo cae o si una GPU está saturada.
- **Cambios sin rastro.** Las configuraciones se tocan a mano y no hay forma de saber qué se cambió ni de volver atrás.

## 4. Propuesta

**Un servidor Linux sin escritorio. Todo corre en contenedores, se entra solo por web o API, y la configuración vive en un repositorio git.**

### 4.1 Sistema operativo: Ubuntu Server 24.04 LTS

- **Las herramientas de GPU están pensadas para Linux.** vLLM, NVIDIA Container Toolkit y la monitorización de GPU (DCGM) son nativas de Linux. Sobre WSL funcionan peor y con más limitaciones.
- **Servicios que arrancan solos.** Con systemd y Docker, todo vuelve tras un reinicio sin que nadie inicie sesión.
- **Sin escritorio.** No hay nada que "abrir".
- **No hay alternativa razonable en Windows.** Mantener Windows y pasar las GPUs a una máquina virtual Linux (DDA) solo existe en Windows Server, no en Windows 11 Pro.

### 4.2 Arquitectura

```
          Internet / red del ITIC
                    │   Cloudflare Tunnel (sin puertos abiertos)
                    ▼
┌─ Proxy inverso (Traefik o Caddy) + HTTPS ─────────────────────────┐
│  chat.<dominio>    → Open WebUI       login Google @iticbcn.cat   │
│  api.<dominio>     → LiteLLM          claves por profe/grupo      │
│  <app>.<dominio>   → aplicaciones     p. ej. CoorDUAL             │
│  admin.<dominio>   → Grafana, panel   solo administradores        │
└───────────────────────────────────────────────────────────────────┘
                    │
     ┌──────────────┴───────────────┐
     ▼                              ▼
┌─ Capa LLM ───────────────────┐  ┌─ Aplicaciones ───────────────┐
│ LiteLLM: claves, cuotas, logs│  │ un stack docker compose      │
│ GPU 0: vLLM, modelo de clase │  │ por aplicación, con su red   │
│ GPU 1: 2.º modelo / vídeo /  │  │ y su base de datos propias   │
│        entrenamiento         │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘
┌─ Transversal ─────────────────────────────────────────────────────┐
│ Monitorización: Prometheus + DCGM (GPU) + Grafana + Uptime Kuma   │
│ Copias: restic → 2.º disco + copia fuera del servidor             │
│ Configuración: repo git "infra-super", una carpeta por servicio   │
└───────────────────────────────────────────────────────────────────┘
```

### 4.3 Las piezas

| Pieza | Qué hace | Por qué |
|---|---|---|
| **vLLM** | Sirve los modelos en la GPU | Atiende muchas peticiones simultáneas con *batching* continuo. Es lo que necesita una clase entera. |
| **LiteLLM** | Puerta única de la API, compatible con OpenAI | Cada profesor, grupo o alumno tiene su clave, con cuota y registro de uso. Los ejercicios de Python o de agentes funcionan igual que contra OpenAI, pero en local y gratis. Se puede cortar el acceso a un grupo. |
| **Open WebUI** | Chat tipo ChatGPT | Login con la cuenta de Google del centro. Grupos por curso y modelos visibles según el grupo. Nadie necesita cuenta en el servidor. |
| **Ollama** | Probar modelos nuevos | Se queda solo como banco de pruebas, no para servir a clase. |
| **ComfyUI** | Imagen y vídeo (I+D+i) | Ya funciona. Pasa a ser un contenedor más. |
| **Traefik / Caddy** | Proxy inverso y HTTPS | Un punto de entrada con certificados automáticos. |
| **Cloudflare Tunnel + Access** | Acceso desde fuera | Sin abrir puertos. Las rutas de administración, solo para cuentas autorizadas. |
| **Prometheus + Grafana + Uptime Kuma** | Monitorización | Uso de GPU, memoria y servicios. Aviso si algo cae. |
| **restic** | Copias de seguridad | Copias cifradas e incrementales, a otro disco y fuera del servidor. |

### 4.4 Reparto de las GPUs

Lo dejamos escrito para evitar conflictos:

- **GPU 0, siempre:** el LLM de clase. No se toca.
- **GPU 1, flexible:**
  - En horario lectivo: un segundo modelo (por ejemplo, de código o multimodal).
  - Fuera de horario: vídeo (ComfyUI), entrenamiento y *fine-tuning*.
- **Las dos juntas:** solo en ventanas planificadas, para un modelo grande (~70 B).

### 4.5 Acceso

| Quién | Cómo entra | A qué |
|---|---|---|
| Administradores (1-2) | SSH con clave, cuenta nominal, por el túnel | Sistema operativo y configuración |
| Profesorado | Web (Google @iticbcn.cat) y API con su clave | Chat, API, sus aplicaciones |
| Alumnado | Web (Google @iticbcn.cat) y API con clave de grupo o personal | Chat y API, con cuota |
| Proyectos de compañeros | Contenedor propio o JupyterHub con GPU y cuota | Su entorno, sin tocar el sistema |

- **No hay cuentas compartidas.**
- **Los cambios se hacen en el repo `infra-super`** y se aplican con `docker compose up`. Así cada cambio tiene autor, fecha y vuelta atrás.

### 4.6 Datos y RGPD

- **Los datos no salen del centro.** Las conversaciones del chat y los datos de las aplicaciones (CoorDUAL tiene datos del alumnado) se quedan en el servidor.
- **Copias cifradas, y la copia externa en un destino del centro.** Por ejemplo, un NAS o el Drive institucional.
- **Registro mínimo en LiteLLM:** solo el consumo por clave, no el contenido.
- Es un argumento a favor frente a usar servicios externos de IA con el alumnado.

## 5. Qué capacidad tendremos

Estimaciones orientativas; se validarán con pruebas de carga.

| Escenario | GPU | Modelo de ejemplo | Uso |
|---|---|---|---|
| Modelo de clase | 1 × 48 GB | 24-32 B en FP8 (familias Qwen, Mistral, Gemma) | 25-30 alumnos a la vez con respuesta fluida |
| Dos modelos en paralelo | 2 × 48 GB | Uno general + uno de código o visión | Dos grupos con necesidades distintas |
| Modelo grande | 2 × 48 GB juntas | ~70 B cuantizado (4-bit) | Demostraciones, evaluaciones, proyectos de I+D |
| Vídeo / imagen | 1 × 48 GB | Modelos de vídeo en ComfyUI | Fuera del horario lectivo |

## 6. Comparativa

| | Ahora | Propuesta |
|---|---|---|
| Sistema | Windows 11 Pro de escritorio + Ubuntu en WSL | Ubuntu Server 24.04 LTS, sin escritorio |
| Cuentas | Una cuenta compartida de administrador | 1-2 administradores nominales con SSH por clave |
| Uso por profes y alumnos | Entrando al escritorio o a WSL | Solo web (chat) y API |
| Arranque | Depende de una sesión abierta | Todo arranca solo tras un reinicio |
| Servir LLM | Dos Ollama que chocan en el mismo puerto | vLLM preparado para una clase entera; Ollama solo para pruebas |
| API para clase | No hay | LiteLLM compatible con OpenAI, con claves, cuotas y uso |
| Chat | Open WebUI lanzado a mano | Open WebUI fijo, login Google del centro, grupos por curso |
| GPUs | Sin reparto | GPU 0 para clase; GPU 1 flexible; política escrita |
| Aplicaciones | Mezcladas en un Ubuntu compartido | Un stack aislado por aplicación |
| Copias | Ninguna, un solo disco | Copia nocturna a un 2.º disco + copia fuera |
| Monitorización | Ninguna | Grafana + avisos de caída |
| Configuración | Cambios a mano, sin rastro | Repo git con historial y vuelta atrás |
| Acceso remoto | Túnel Cloudflare + SSH con clave (ya hecho) | Igual, más Cloudflare Access en las rutas de administración |

## 7. Plan de migración

| Paso | Qué | Tiempo |
|---|---|---|
| 1 | **Inventario y copia.** Usuarios y chats de Open WebUI, modelos, proyectos de compañeros y la base de datos de CoorDUAL. | ½ día |
| 2 | **Hablar con quien usa hoy la máquina,** para dar sitio a sus proyectos en la nueva arquitectura. | — |
| 3 | **Reinstalar con Ubuntu Server,** drivers NVIDIA, Docker y el túnel. | ½ día |
| 4 | **Montar el repo `infra-super`:** proxy, LiteLLM, vLLM, Open WebUI, monitorización y copias. | 1-2 días |
| 5 | **Restaurar** Open WebUI, CoorDUAL y ComfyUI como stacks. | ½ día |
| 6 | **Prueba de carga con un grupo real** y ajuste de cuotas. | 1 sesión de clase |

Casi todo se puede hacer en remoto. El corte de servicio se limita a la reinstalación, que se puede hacer en un día sin clase.

## 8. Qué necesitamos decidir

- **Aprobación de la reinstalación** con Ubuntu Server.
- **Subdominio** para el servicio, del centro o uno propio, y si el chat es accesible desde fuera del centro o solo desde dentro.
- **Política de uso:** cuotas por alumno, horarios de la GPU 1 y quién puede pedir las dos GPUs.
- **Administradores:** quién, como máximo dos personas.
- **Un segundo NVMe** de 2-4 TB para copias y modelos. Es la mejora de hardware más rentable (unos 150-300 €).
- **Opcional:** ampliar la RAM, que tiene 4 ranuras libres, si se quieren cargar modelos grandes en CPU o tener más contenedores.
