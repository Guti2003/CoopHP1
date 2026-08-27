# Los tres arreglos

Estado a 2026-08-27. Nada de esto está compilado ni probado — falta `ucc.exe`.

---

## BUG 1 — Ron congelado · **YA APLICADO** en las fuentes

`CoopPuppet.uc`, en el bloque `defaultproperties` reconstruido:

```unrealscript
Mesh=SkeletalMesh'HarryPotter.skharryMesh'    // era skronMesh
```

Y en `CoopManager.uc`:

```unrealscript
PuppetZOffset=0.000000                        // era 12.0
```

**Verificado antes de escribirlo:** `skharryMesh` existe en `HarryPotter.u`, y las
seis secuencias que fallaban (`breath`, `Jump`, `climb32`, `climb96start`,
`climb96end`, `runback`) están en ese mismo paquete.

**Por qué también cambia el ZOffset:** los 12 eran para re-basar el centro del
cilindro de Harry al de Ron. Con el muñeco siendo Harry, esa corrección sobra.
Si tu config guardada aún trae 12, arréglalo en partida con `CoopZ 0`.

**Riesgo residual:** `CollisionRadius=17` es una suposición. Da igual en la
práctica, porque `PostBeginPlay` desactiva la colisión de inmediato — es el
invariante más importante del mod (que el muñeco no dispare triggers dos veces).

---

## BUG 2 — `CoopHost` no re-hospeda · **NO aplicado**

`CoopManager.Host()` destruye el socket y pide el mismo puerto en el mismo frame:

```unrealscript
DisconnectLink();              // Link.Destroy()
Link = Spawn(class'CoopLink');
Link.StartHost(port);          // BindPort(7777, false) -> falla
```

**Arreglo propuesto — no destruir el link al desconectar.** En vez de tocar
`Host()`, hacer que `DisconnectNow()` conserve el socket y solo marque la sesión
como cerrada; `Host()` reutiliza el link si ya está bindeado al puerto pedido.
Evita la recreación entera, que es lo que falla.

**Alternativa más simple y más fea:** en `CoopLink.StartHost`, si
`BindPort(port, false)` devuelve 0, reintentar en el siguiente tick en vez de
rendirse. El puerto se libera solo en cuanto el actor viejo pasa por la recogida
de basura.

**No lo escribo porque no puedo probarlo.** Los dos toques cambian el ciclo de
vida del socket, que es justo donde un error no se ve hasta que dos personas
intentan jugar. Mientras tanto el workaround funciona: `CoopHost 7778`.

---

## BUG 3 — El mapa es el nombre del save · **NO aplicado, y hace falta medir antes**

```unrealscript
function string MapName()
{
    return string(Level.Outer.Name);    // devuelve "save0" al cargar partida
}
```

Aquí **no se debe adivinar**. `Level.Outer.Name` da el paquete, que tras cargar
una partida es el savegame. Los candidatos para sustituirlo son:

| Candidato | Duda |
|---|---|
| `Level.GetURLMap()` | Debería dar `LEV_TUT1B.unr`. ¿Qué devuelve tras cargar un save? |
| `Level.Title` | Es el título legible, no un nombre de mapa. No sirve para `ClientTravel`. |
| `string(Level.Outer.Name)` tras el primer travel | El log muestra que acaba siendo correcto — pero no de entrada. |

**Antes de tocar nada, medir.** Añadir a `PostBeginPlay` del manager una línea
que escriba los tres valores al log, jugar diez minutos cargando partida y
cruzando una puerta, y mirar cuál se comporta bien en los dos casos:

```unrealscript
log("[HP1Coop] MAPDIAG outer=" $ string(Level.Outer.Name)
  $ " urlmap=" $ Level.GetURLMap()
  $ " title=" $ Level.Title);
```

Es media hora de trabajo y elimina la única incógnita real que queda. Sin ese
dato, cualquier arreglo es una apuesta — y este bug es el que impide jugar en
serio, así que no conviene apostar.

**Ojo con el efecto colateral:** la lógica de seguimiento hace
`ClientTravel(RemoteMap)`. Sea cual sea el valor que se elija, tiene que ser algo
a lo que `ClientTravel` pueda viajar de verdad. `Level.Title` no lo es.

---

## Para compilar cuando llegue el toolkit

```
System\HP1Coop\Classes\*.uc     <- estos cuatro archivos
EditPackages=HP1Coop            <- en el ini de compilación
ucc make
```

Si el compilador protesta, sospechar primero de los `defaultproperties`
reconstruidos y de posibles `#exec` de cabecera, que tampoco viajan en el
`ScriptText`.
