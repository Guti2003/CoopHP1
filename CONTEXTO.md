# HP1 Co-op — contexto del proyecto

*Reconstruido el 2026-08-27 a partir de `HP1CoopHito3/` (el `.u` compilado conserva
los comentarios del fuente) y del resumen de cierre de la sesión de claude.ai/code,
pegado por Miguel. La sesión original no es legible desde esta máquina.*

## Qué es

Mod cooperativo para **Harry Potter y la Piedra Filosofal (PC, 2001)**, motor
Unreal Engine 1. Dos jugadores, cada uno con su propia partida, se ven mutuamente
en el mapa. El compañero se dibuja como **Ron**.

Portado desde `hp2-coop-multiplayer` (jenyaalexanov, MIT), que hace lo mismo para
La Cámara Secreta. Recursos de modding HP1: metallicafan212 y Han / OldUnreal.

## Estado actual — `HP1CoopHito3/`

```
HP1Coop/
  HP1Coop.u              52.760 bytes  (paquete compilado)
  Instalar.bat / Desinstalar.bat
  installer/Install.ps1  installer/Uninstall.ps1
  LEEME.txt
```

Esto **es** el Hito 3: hechizos sincronizados. El `LEEME.txt` todavía se titula
"Hito 1" — el texto va por detrás del binario. **Pendiente: actualizar el encabezado.**

Los dos jugadores deben instalar el **mismo** archivo: 52.760 bytes exactos.

### Funciona
- Pose sync: posición, rotación, velocidad, animación, HP — 20 Hz
- Seguimiento de cambio de mapa (`ClientTravel`)
- **Hechizos**: el proyectil existe de verdad en ambas partidas (vuela, choca, explota)
- `CoopStatus` con ping estimado (media móvil `(p*3+n)/4`)

### No funciona todavía
- Objetos recogidos (grageas, cromos, ranas) → paquete `PICK`
- Enemigos
- Puertas, mecanismos, cinemáticas → paquete `LTRIG` (secretos de Lumos)
- Progreso de partida

## Arquitectura

Cuatro clases:

| Clase | Rol |
|---|---|
| `CoopConsole` | Punto de entrada. Extiende `UWindow.WindowConsole`. Sobrevive al cambio de nivel. |
| `CoopManager` | Corazón del mod. Se destruye en cada travel; la consola lo re-crea. |
| `CoopLink` | Envoltorio de socket UDP sobre `IpDrv.UdpLink`. |
| `CoopPuppet` | Fantasma del jugador remoto, dibujado con la malla de Ron (`skronMesh`, en el paquete `HarryPotter`, no en `HPModels` como en HP2). |

### Decisión clave: consola, no `ServerActors`
UE1 solo instancia `ServerActors` cuando el motor arranca **como servidor**, y el
`PlayerPawn` local no existe garantizadamente en ese momento. Se probó y **no
funciona**. Enganchar por `Console=` sí: la consola persiste entre niveles y
re-crea el manager sin hooks en el ini.

### Diferencia con HP2Coop: no hay inyección de paquetes

Esta es **la lección central del proyecto**. Toda la planificación asumía que para
sincronizar hechizos había que interceptar `Harry.Cast()`, y que eso obligaba a
inyectar código en `HarryPotter.u` (HP2Coop lo hace con `class CoopHarry injects
harry`, palabra clave no estándar del compilador de M212).

**La premisa era falsa.** `Harry.Cast()` llama a `baseWand.castspell()`, y la
varita ya lleva su propia contabilidad:

```unrealscript
var baseSpell LastCastedSpell;   // en baseWand.uc
```

El juego ya apuntaba el dato. Detectar un lanzamiento es una comparación de
punteros por tick contra `baseWand(Player.Weapon).LastCastedSpell` — sin hook, sin
inyección, sin recorrer actores.

Y como `baseSpell extends Projectile`, el hechizo del compañero se recrea con un
`Spawn` normal (sin owner, a propósito) más velocidad. A partir de ahí corre la
lógica original del juego: vuela, colisiona y explota solo. No es un adorno visual
— el hechizo existe de verdad en las dos partidas y afecta al mundo en ambas.

> **Método general, aplicable a lo que queda:** antes de asumir que hay que
> interceptar una llamada, mirar si el juego ya guarda ese dato en algún sitio
> accesible.

### El bug del "zombi" tras cambio de nivel
La consola sobrevive al travel pero el `CoopManager` no. UE1 no marca `bDeleteMe`
en el manager viejo, así que la consola conserva una referencia muerta. Se resuelve
comprobando `Coop.Level == Viewport.Actor.Level` además de `!bDeleteMe`.

### Altura de Ron
Harry tiene `CollisionHeight=42`, Ron `CollisionHeight=30`. La `Location` remota se
re-basa del centro del cilindro de Harry al de Ron. El offset exacto depende de
orígenes de malla horneados en `HarryPotter.u` que no se pueden leer del fuente,
de ahí `CoopZ <n>` ajustable en vivo (Ron se hundía hasta la cintura en la primera
prueba de juego).

## Protocolo — texto sobre UDP, delimitado por `|`

Idéntico a HP2Coop v1 (interoperable). Prefijo `HPCOOP|1`.

```
HPCOOP|1|HELLO|name
HPCOOP|1|HELLOACK|name
HPCOOP|1|BYE
HPCOOP|1|PING|seq          HPCOOP|1|PONG|seq
HPCOOP|1|MAP|mapfile.unr
HPCOOP|1|S|map|x|y|z|yaw|pitch|vx|vy|vz|anim|rate|hp
HPCOOP|1|SP|seq|class|x|y|z|pitch|yaw    (se envía 3x, deduplicado por seq)
```

Un disparo es un evento único, no un flujo: si se pierde el paquete el hechizo no
ocurre. Por eso se manda tres veces y el receptor descarta repeticiones por
`LastRecvSpellSeq`.

Puerto por defecto **UDP 7777**. El host hace `BindPort(port, false)`; el cliente
`BindPort(0, true)`. Se re-crea el socket en cada travel.

## Comandos de consola (TAB)

```
CoopHost [port]              CoopConnect <ip> [port]      (solo IP numérica)
CoopStatus                   CoopZ <n>
CoopDisconnect               CoopDebug
```

Solo funcionan **en partida**, no en el menú (`Startup.unr` / `Entry.unr`).

## Instalador — lecciones aprendidas (documentadas en Install.ps1)

1. **Dos ficheros ini importan**, y esto se aprendió por las malas:
   - `<Juego>\System\Default.ini` — la semilla
   - `%USERPROFILE%\Documents\Harry Potter\HP.ini` — el que el juego **realmente lee**

   Parchear solo `Default.ini` no hace nada en una máquina que ya abrió el juego.

2. **ANSI sin BOM.** Escribir un BOM UTF-8 impide que el motor arranque (verificado).

3. Parche: `Console=HPMenu.HPConsole` → `Console=HP1Coop.CoopConsole`.
   Además fuerza `bDebugMode` y `ConsoleKey=9` (IK_Tab), porque la consola viene
   desactivada de fábrica.

4. Comprobación de versión: `System\HarryPotter.u` debe medir **13.972.287 bytes**
   (la edición contra la que se compiló). Si no, avisa y pide confirmación.

5. Hace backup `.hp1coop-backup` de todo lo que toca. No modifica ningún archivo
   original del juego.

## Problema conocido ajeno al mod

El juego de 2001 usa renderizador por software a pantalla completa, que Windows
10/11 ya no permite. Arreglo: en `Documentos\Harry Potter\HP.ini`, las dos líneas
`StartupFullscreen=True` → `False`. Ese archivo está fuera de la carpeta del juego,
así que reinstalar el juego no lo arregla.

## Qué está probado y qué no

**Probado** (con paquetes `SP` sintéticos, sin jugador humano): el receptor recrea
el hechizo, resuelve las clases (`spellFlip` y `HPBase.spellFlip`), ejecuta la
física del juego y no duplica. Dedup verificado: 6 paquetes entran, 2 hechizos
salen. Cero warnings.

```
[HP1Coop] hechizo remoto: spellFlip
******** Explode:Lev_Tut1.spellFlip0     <-- código del propio juego
```

**Sin probar: el lado emisor.** Requiere que una persona lance un hechizo de verdad
con el ratón. Si con `CoopDebug` activado el log dice `hechizo lanzado: <clase>`,
va bien. **Este es el test pendiente**, y bloquea el siguiente hito.

El log del juego está en `Documentos\Harry Potter\HP.log`; todas las líneas del mod
empiezan por `[HP1Coop]`.

## Hoja de ruta realista

**Alcanzable, probablemente pronto** — objetos recogibles (grageas, cromos, ranas)
y secretos de Lumos. Debería aplicar la misma lección de los hechizos: buscar dónde
apunta ya el juego ese estado.

**Difícil de verdad** — enemigos, puertas, mecanismos y cinemáticas. Aquí no hay
atajo equivalente: la IA de cada enemigo corre por separado en cada partida y no
existe un "último estado" que copiar. Sincronizarlo es rehacer el modelo de
simulación, no detectar un evento. El coop de HP2 tampoco lo tiene.

Conclusión honesta: "terminado" con progreso compartido completo **no es realista**.
"Terminado" como recorrer Hogwarts juntos, viéndoos, moviéndoos y lanzando hechizos
que afectan a los dos mundos — eso está a un test de distancia.

## Falta en el repo

- **No hay fuentes `.uc` en disco**, solo el `.u` compilado.
- **No está el HANDOFF** que la sesión original menciona (recoge el método general
  de "mirar si el juego ya apunta el dato").

Ambos quedaron en el entorno de la sesión de claude.ai/code. Si se sigue
desarrollando aquí, hay que recuperarlos primero.

---

# Bugs confirmados en juego real (2026-08-27, sesión con dos jugadores)

Primera partida real: Miguel (cliente) + amigo (host) por VPN tipo Radmin
(`25.26.239.149`). La red funcionó: conexión, `HELLO`, stream de estado,
reconexión automática tras cambiar de nivel (`manager up on LEV_TUT1B` →
reconectado solo) y `peer timed out` limpio al irse el otro.

## BUG 1 — Ron no anima (crítico, y es un error de diseño)

**Síntoma:** el compañero se ve congelado al saltar y al escalar.

**Causa raíz:** `skronMesh` no contiene el set de animaciones de Harry. El emisor
manda `Player.AnimSequence` (nombres de Harry) y el muñeco intenta reproducirlos
sobre el cuerpo de Ron. En `HP.log`, 21.352 líneas en una sola sesión:

```
16786 x  Sequence 'breath' not found in Mesh 'skronMesh'      <- idle
  936 x  Sequence 'runback' not found
  583 x  Sequence 'climb96end' not found                       <- escalar
  151 x  Sequence 'climb32' not found                          <- escalar
  140 x  Sequence 'climb96start' not found                     <- escalar
   59 x  Sequence 'Jump' not found                             <- saltar
  772 x  look2 | 330 x look3 | 561 x wizardcardcollect
  312 x  adjustglasses | 295 x scratch | 199 x lookwand | 157 x wave
   70 x  knockback2
```

**Agravante — el bucle de reintento.** En `CoopPuppet.Tick`:

```unrealscript
if (TargetAnim != '' && AnimSequence != TargetAnim)
    PlayAnim(TargetAnim, TargetAnimRate, 0.15);
```

Como `PlayAnim` falla, `AnimSequence` nunca iguala a `TargetAnim`, así que se
reintenta **cada tick indefinidamente**. El muñeco no se ve "mal animado": se ve
congelado, porque se reinicia desde el fotograma 0 sesenta veces por segundo.
Explica los 16.786 `breath` de un personaje simplemente quieto.

**Origen del error:** los propios comentarios del mod anotan que HP2Coop usa
`SkeletalMesh'HPModels.skharryMesh'` para el muñeco. El port a HP1 lo cambió a
Ron por criterio estético, sin caer en que los nombres de animación transmitidos
son los de Harry.

**Arreglos posibles (los dos exigen recompilar):**
1. Usar la malla de Harry para el muñeco. Arregla todo de golpe; coste: se ven dos Harrys.
2. Tabla de traducción de nombres Harry -> Ron. Conserva a Ron; hay que enumerar
   antes las secuencias reales de `skronMesh`.
3. En cualquier caso, **guardar el nombre pedido en una variable propia** para no
   reintentar `PlayAnim` en cada tick cuando la secuencia no existe.

## BUG 2 — `CoopHost` falla al re-hospedar tras `CoopDisconnect`

**Síntoma:** host -> `CoopDisconnect` -> `CoopHost` -> `failed to bind UDP port 7777`.

**Causa:** en `CoopManager.Host()` el socket se destruye y se vuelve a pedir el
mismo puerto en el mismo frame:

```unrealscript
DisconnectLink();              // Link.Destroy()
Link = Spawn(class'CoopLink');
Link.StartHost(port);          // BindPort(7777, false)
```

El socket anterior aún no lo ha liberado a nivel de SO. Y como pide el puerto
exacto (`false` = no buscar el siguiente libre), no se recupera solo.

**Workaround sin recompilar:** re-hospedar en otro puerto (`CoopHost 7778`, y el
otro `CoopConnect <ip> 7778`), o reiniciar el juego.

**Arreglo:** reintentar el bind con backoff, o caer a `BindPort(port, true)` y
anunciar el puerto realmente obtenido.

## Nota — `CoopDebug` hace falta para el test de hechizos

`LogMsg("hechizo lanzado: ...")` está condicionado a `bShowDebug`. En esta sesión
no se activó, así que **el lado emisor de los hechizos sigue sin verificarse**.
Hay que escribir `CoopDebug` antes de jugar.

## BUG 3 — La identidad del mapa es el nombre del SAVE, no el del nivel (el más grave)

**Síntoma:** los dos jugadores se ven bien al cargar partida, y dejan de verse en
cuanto uno cruza una transición de nivel (reportado al pasar la puerta hacia el
desafío de flipendo). El que se queda atrás desaparece para siempre.

**Causa raíz:**

```unrealscript
function string MapName()
    return string(Level.Outer.Name);
```

Al cargar una partida guardada, `Level.Outer.Name` no es el nivel: es el **paquete
del savegame**. Evidencia en `HP.log`:

```
[HP1Coop] manager up on save0          <- al cargar partida
[HP1Coop] Harry moved to save0         <- el peer anuncia "save0"
[HP1Coop] manager up on LEV_TUT1B      <- tras cruzar la puerta
```

Los dos cargaron `save0`, ambos anunciaban `"save0"`, y por eso coincidían. Al
cruzar la puerta uno pasa a `LEV_TUT1B` y el otro sigue en `"save0"`.

**Dónde rompe:**

```unrealscript
// UpdatePuppet()
if (RemoteMap != MapName())
    HidePuppet();               // "save0" != "LEV_TUT1B" -> desaparece
```

**Bomba de relojería latente** — la lógica de seguimiento:

```unrealscript
if (!bIsHost && Player != None && RemoteMap != MapName())
    Player.ClientTravel(RemoteMap, TRAVEL_Absolute, false);   // ClientTravel("save0")
```

Intentaría viajar a un mapa llamado `save0`, que no existe. No observado todavía,
pero es un cuelgue esperando a ocurrir.

**Sin workaround.** A diferencia del bug del puerto, no hay nada que teclear. Lo
único que lo mitiga es que los dos avancen juntos sin que uno cruce una transición
antes que el otro.

**Arreglo:** obtener el nombre real del nivel por otra vía (`Level.Title`, la
propiedad del `LevelInfo`, o el nombre del `.unr` cargado) en lugar de
`Level.Outer.Name`. Comprobar qué devuelve cada opción tras cargar un savegame,
que es el caso que rompe.

## Estado del entorno de compilación (2026-08-27)

Juego instalado en `E:\Harry Potter y la Piedra Filosofal` — `HarryPotter.u` mide
13.972.287 bytes, coincide con la versión contra la que se compiló el mod. Mod
instalado y verificado.

**No hay compilador.** Ni `ucc.exe` en `System\`, ni nada en `Support\` (solo
instaladores del juego), y `HP.exe` no acepta `make`. Los tres bugs confirmados
están bloqueados por esto: hace falta el toolkit de modding de HP1
(metallicafan212 / OldUnreal) y las fuentes `.uc`.

**Decisión tomada por Miguel:** para el BUG 1, adelante con la malla de Harry.
Ver dos Harrys es aceptable. Es el arreglo de una línea.
