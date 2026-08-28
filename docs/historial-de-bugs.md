# Historial de bugs

Ocho fallos encontrados y arreglados. **Siete de los ocho aparecieron jugando**,
no leyendo código — y varios se resolvieron gracias a un detalle que solo se ve
desde dentro de la partida.

---

## BUG 1 — El compañero se veía congelado

**Síntoma:** el otro jugador aparecía inmóvil al saltar y al escalar.

**Causa:** el muñeco se dibujaba con la malla de Ron, y `skronMesh` no contiene
el set de animaciones de Harry. Como lo que viaja por la red son nombres de
animación de Harry, `PlayAnim` fallaba. En un solo registro de partida:

```
16786 x  Sequence 'breath' not found in Mesh 'skronMesh'      <- estar quieto
  583 x  climb96end       151 x climb32        140 x climb96start
   59 x  Jump             936 x runback
```

**Agravante.** La condición era `AnimSequence != TargetAnim`. Como `PlayAnim`
fallaba, `AnimSequence` nunca llegaba a igualar el objetivo, así que se
reintentaba **cada fotograma**: la animación se reiniciaba 60 veces por segundo.
No es que se viera mal — es que se veía congelada.

**Arreglo:** malla de Harry para el muñeco, y recordar la última animación
intentada para no reintentar en bucle. Se aceptó ver dos Harrys.

---

## BUG 2 — `CoopHost` fallaba al re-hospedar

**Síntoma:** `CoopHost` → `CoopDisconnect` → `CoopHost` daba
`failed to bind UDP port 7777`, y no se recuperaba nunca.

**Causa:** se destruía el socket y se pedía el mismo puerto en el mismo
fotograma. **En UE1 `Destroy()` solo marca el actor:** el socket nativo no se
cierra hasta la recogida de basura, que dentro de una partida puede tardar
muchísimo.

**Arreglo:** no destruir el socket al desconectar. Si ya tenemos uno en el
puerto pedido, se reutiliza.

---

## BUG 3 — Los jugadores se perdían al cambiar de nivel

**Síntoma:** se veían bien y dejaban de verse en cuanto uno cruzaba una puerta.

**Causa:** la identidad del nivel salía de `Level.Outer.Name`. Y en HP1 **una
partida guardada es un mapa**: cargar ejecuta literalmente `open save0.usa`. Los
dos cargaban `save0`, los dos decían llamarse `save0`, y al cruzar la puerta uno
pasaba a `LEV_TUT1B` mientras el otro seguía en `save0`.

Peor: la lógica de seguimiento habría intentado viajar a un mapa llamado
`save0`, que no existe.

**Arreglo:** `Level.LevelEnterText`, que es de donde lo saca el propio juego
(`HPConsole.doLevelSave`) y que viaja dentro del savegame.

---

## BUG 4 — El compañero desaparecía para siempre al morir alguien

**Síntoma:** al morir uno, el otro dejaba de verse. La sesión seguía viva y los
hechizos se seguían oyendo. **Solo se recuperaba si morían los dos.**

Ese detalle fue lo que lo resolvió: morir era lo único que reconstruía el
muñeco, porque al recargar se creaba todo de cero.

**Causa, en dos partes:**

1. Al muñeco le faltaba `Health` en sus propiedades, así que nacía con 0. Para
   el motor eso es un cadáver, y la limpieza de pawns se lo llevaba.
2. La condición de recreación era `Puppet == None`. Al ser destruido, la
   referencia **no queda a `None`**: queda apuntando a un actor muerto con
   `bDeleteMe`. No se recreaba nunca más.

Es el mismo patrón del bug "zombi" que ya estaba documentado para el manager,
sin aplicar al muñeco.

---

## BUG 5 — Wingardium Leviosa desincronizaba las partidas

**Síntoma:** los objetos terminaban en lugares distintos en cada mundo. En el
registro, **6.081 avisos** en una sola partida:

```
SPELLPostLEV ... Accessed None: Target
```

**Causa:** replicar un hechizo funciona porque es un *evento* — sale, vuela,
choca y explota, y la física hace el resto igual en ambos mundos. Leviosa no es
un evento: es una manipulación **sostenida**, con un objeto agarrado que el
jugador mueve con la puntería. La copia remota nacía sin objeto.

**Arreglo:** no replicar los hechizos sostenidos. Que cada mundo sea coherente
consigo mismo es preferible a dos mundos que discrepan.

**Este no era un descuido**, a diferencia de los demás: es un límite del enfoque
de replicar eventos.

---

## BUG 6 — Se perdía la conexión al cambiar de nivel (solo al anfitrión)

**Síntoma:** tras cambiar de nivel, el cliente llamaba y nadie contestaba.

La asimetría fue la pista: **solo le pasaba al que hospedaba.**

**Causa:** la consola sobrevive al cambio de nivel y seguía apuntando al manager
del nivel anterior. Mientras esa referencia existiera, el manager viejo no era
basura recogible, y con él sobrevivía su socket **reteniendo el puerto 7777**.

Al cliente no le afectaba porque pide un puerto efímero, y de esos siempre hay
libres.

**Arreglo:** soltar el socket explícitamente antes de olvidar el manager viejo.
Mismo fondo que el BUG 2.

---

## BUG 7 — Al cliente se le borraba el inventario en cada cambio de nivel

**Síntoma:** *"tengo 0 puntos y voy por donde se aprende Lumos"*.

**Causa:** el mod seguía al anfitrión con

```unrealscript
Player.ClientTravel(mapa, TRAVEL_Absolute, false);
```

`TRAVEL_Absolute` con `bItems=false` significa literalmente **"viaja sin
llevarte nada"**. Y lo que se pierde así es justo lo que `baseHarry` marca como
`travel`: `numBeans`, `numStars`, `numHousePointsHarry` y `WizardCards[25]`.

Solo afectaba al cliente porque el que sigue es el cliente.

**El juego nunca usa `TRAVEL_Absolute`.** Su camino es
`ChangeLevel(mapa, true)` → `ServerTravel` → `ClientTravel(URL, TRAVEL_Relative, true)`.

**Arreglo:** usar esa misma ruta en vez de inventar otra.

Lo ya perdido no se recuperó.

---

## BUG 8 — Las grageas salían por duplicado

**Síntoma:** *"si hay 4 grageas en realidad nos dan 8; yo recojo las 4 mías y él
recoge las 4 que le aparecen a él"*.

**Causa:** cada partida tiene su propio juego de objetos. Compartiendo solo la
*cuenta*, cada uno recogía sus 4 y además recibía las 4 del otro.

**Arreglo:** al recoger algo, se avisa a los demás con el **nombre del actor** y
estos lo destruyen. Los mapas son idénticos, así que el nombre identifica el
objeto sin ambigüedad. El crédito sigue llegando solo por el paquete de
inventario — darlo también al destruir sería volver a duplicar.

**De paso se corrigió un criterio equivocado:** los puntos de casa dejaron de
compartirse. No son objetos del mundo, se conceden por hacer algo, y como todos
hacen la misma lección ya los ganaban por su cuenta. Compartirlos era el error.

---

## Dos cosas que enseñó esta lista

**En UE1, un socket no se cierra cuando tú quieres, sino cuando pasa el
recolector de basura.** Los bugs 2 y 6 son la misma trampa por dos caminos
distintos.

**Una referencia a un actor destruido no queda a `None`.** Los bugs 4 y 6
también comparten eso.
