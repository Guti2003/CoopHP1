# Arquitectura y decisiones de diseño

Notas técnicas de HP1 Co-op. Para instalar y jugar, ver el
[README](../README.md).

---

## La idea que sostiene todo el mod

> **Antes de asumir que hay que interceptar una llamada del juego, mirar si el
> juego ya guarda ese dato en algún lugar accesible.**

Esto no es una frase bonita: es lo que hizo viable el proyecto, y se ha repetido
cuatro veces.

**Los hechizos.** Toda la planificación asumía que sincronizarlos exigía
interceptar `Harry.Cast()`, y que eso obligaba a inyectar código dentro de
`HarryPotter.u`. Era falso: `baseWand` ya apuntaba su último disparo en
`LastCastedSpell`. Detectar un lanzamiento es una comparación de punteros por
tick.

**El nombre del nivel.** `Level.Outer.Name` daba `save0` tras cargar partida
(ver BUG 3). El juego sí sabía dónde estaba: lo saca de `Level.LevelEnterText`.

**El inventario.** No hace falta enganchar la recogida de una gragea:
`baseHarry` ya lleva `numBeans`, `numStars` y `WizardCards[]`, y el juego trae
`AddBeans()`, que además refresca el HUD.

**Qué objeto se ha recogido.** Tampoco: la gragea pasa al estado `killbean` y la
estrella a `pickupstar` justo antes de destruirse.

---

## Las cuatro clases

| Clase | Rol |
|---|---|
| `CoopConsole` | Punto de entrada y comandos. Extiende `HPConsole`. **Sobrevive al cambio de nivel.** |
| `CoopManager` | El corazón. Se destruye en cada cambio de nivel; la consola lo recrea. |
| `CoopLink` | Socket UDP sobre `IpDrv.UdpLink`. Guarda la tabla de direcciones. |
| `CoopPuppet` | El muñeco que representa a otro jugador. Uno por persona. |

### Por qué la consola y no `ServerActors`

Una versión anterior creaba el manager desde
`[Engine.GameEngine] ServerActors=HP1Coop.CoopManager`. **Se probó y no
funciona:** UE1 solo instancia los `ServerActors` cuando el motor arranca como
servidor, y HP1 en un jugador es `NM_Standalone`. Bajo `UCC server` sí
funcionaba, que es lo que hacía la falla tan confusa.

Enganchar por `Console=` sí sirve: la consola se instancia en todos los niveles
y en todos los modos, y el ini del juego ya la redirige.

**Nada de `HarryPotter.u` ni `HPBase.u` se modifica**, así que ninguna de las
mallas ni texturas incrustadas en esos 14 MB corre peligro.

---

## Protocolo — texto sobre UDP

Topología en **estrella**: los clientes solo hablan con el anfitrión y este
reenvía a los demás. Se eligió así para que siga haciendo falta abrir un solo
puerto en un solo router. El precio: si cae el anfitrión, cae la partida.

Cada jugador tiene un *slot*. El 0 es el anfitrión; los clientes reciben el suyo
en el `WELCOME` y lo escriben en cada paquete, de forma que todos saben de quién
es cada cosa. El número que asigna el anfitrión coincide con el del transporte,
así que no hay dos numeraciones que casar.

```
HPCOOP|2|HELLO|nombre|build                 cliente -> anfitrión
HPCOOP|2|WELCOME|slot|nombreHost|build      anfitrión -> cliente
HPCOOP|2|PING|slot|seq   /  PONG|slot|seq
HPCOOP|2|S|slot|mapa|x|y|z|yaw|pitch|vx|vy|vz|anim|rate|hp
HPCOOP|2|MAP|slot|mapa
HPCOOP|2|SP|slot|seq|clase|x|y|z|pitch|yaw     (se manda 3x, dedup por seq)
HPCOOP|2|INV|slot|grageas|estrellas|puntos|cromos   (totales acumulados)
HPCOOP|2|TOOK|slot|nombreDelActor
HPCOOP|2|BYE|slot
```

**Eventos contra flujos.** El estado del jugador es un flujo: si se pierde un
paquete, el siguiente lo corrige. Un hechizo es un evento único: si se pierde,
no ocurre. Por eso va tres veces y el receptor descarta repeticiones por número
de secuencia.

**El inventario va en totales acumulados, no en incrementos.** Así un paquete
perdido se corrige solo con el siguiente. Con incrementos sería una gragea
perdida para siempre.

---

## Decisiones que parecen raras y no lo son

### Los hechizos existen de verdad

Como `baseSpell extends Projectile`, el hechizo del compañero se recrea con un
`Spawn` normal, sin dueño. A partir de ahí corre la lógica original del juego:
vuela, colisiona y explota.

**De ahí salen gratis los mecanismos.** `spellTrigger` dice en su propio código
que solo los hechizos lo disparan — y los hechizos están de verdad en las dos
partidas. Por eso funcionan los calderos, las placas y los secretos de Lumos sin
haber escrito una línea para ello.

### Wingardium Leviosa no se replica

Un hechizo normal es un evento; Leviosa es una **manipulación sostenida** con un
objeto agarrado que el jugador mueve con la puntería durante segundos. La copia
remota nacía sin objeto y desincronizaba las dos partidas (ver BUG 5).

Que cada mundo sea coherente consigo mismo es preferible a dos mundos que
discrepan.

### Los puntos de casa no se comparten

No se recogen del suelo: se conceden por hacer algo. Como todos hacen la misma
lección, todos los ganan por su cuenta. Compartirlos los duplicaría.

### El inventario se duplica, pero el objeto se destruye

Si uno recoge una gragea la tienen todos — no se le quita a nadie. Pero el
objeto desaparece del mundo de los demás, o cada uno recogería el suyo *y*
recibiría el del otro, y cuatro grageas serían ocho (ver BUG 8).

El objeto se identifica por su **nombre de actor**: los mapas son idénticos en
todas las partidas, así que la gragea que aquí se llama `JellyBean17` allí se
llama igual.

---

## Compilar

Hace falta `UCC.exe`, que no viene con el juego. Está en el archivo de
preservación de OldUnreal, junto con las fuentes de UnrealScript de HP1:

<https://archive.org/details/old-unreal-engine-hp1-ss-pc-script-source-headers-precompiled-binaries>

- `Precompiled Binaries/HarryPotterPubSrc11_Binaries_20170323.zip` → `UCC.exe`
- `ScriptSource/HarryPotterScriptSource11.zip` → las 1.247 clases del juego

### Las dos trampas

Costaron varios intentos cada una:

1. **UCC no lee `System\Default.ini`** ni acepta `-ini=`. Lee
   `Documentos\Harry Potter\HP.ini`, igual que el juego. `EditPackages=HP1Coop`
   va ahí.
2. **El paquete va en la raíz del juego**, no dentro de `System`:
   `<Juego>\HP1Coop\Classes\*.uc`. UCC lo busca como `..\HP1Coop\Classes\*.uc`.

Luego, desde `System\`:

```
UCC.exe make
```

El `.u` sale directamente en `System\`, o sea que compilar ya instala.

---

## El instalador — lecciones aprendidas

1. **Importan dos archivos ini**, y esto se aprendió por las malas:
   - `<Juego>\System\Default.ini` — la semilla
   - `Documentos\Harry Potter\HP.ini` — **el que el juego realmente lee**

   Parchear solo el primero no hace nada en una máquina que ya abrió el juego.

2. **ANSI sin BOM.** Escribir un BOM UTF-8 impide que el motor arranque.

3. El parche es `Console=HPMenu.HPConsole` → `Console=HP1Coop.CoopConsole`.
   Además fuerza `bDebugMode` y `ConsoleKey=9` (TAB), porque la consola viene
   desactivada de fábrica.

4. Revisa que `System\HarryPotter.u` mida **13.972.287 bytes**, la edición
   contra la que se compiló.

5. Hace copia de seguridad de todo lo que toca y no modifica ningún archivo
   original del juego.

---

## Qué no va a llegar

**Enemigos y cinemáticas.** La IA de cada enemigo corre por separado en cada
partida y no existe un "último estado" que copiar: sincronizarlo es rehacer el
modelo de simulación, no detectar un evento. El coop de HP2 tampoco lo tiene.

**Progreso de partida compartido.** Cada uno mantiene su propio guardado.

Dicho de otro modo: esto no es *Hogwarts cooperativo completo*, y no lo será.
Es recorrer el castillo juntos, viéndose, lanzando hechizos que afectan a los
dos mundos y compartiendo lo que encuentran — que resultó ser bastante más de lo
que el plan original daba por posible.
