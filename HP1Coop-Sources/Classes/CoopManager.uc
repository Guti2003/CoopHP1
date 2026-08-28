//================================================================================
// CoopManager - corazon del mod cooperativo de HP1.
//
// DIFERENCIA CLAVE CON HP2COOP
// -----------------------------------------
// HP2Coop engancha el juego recompilando la clase del jugador con
// "class CoopHarry injects harry", una palabra clave no estandar del compilador
// de M212. HP1 no lo necesita. Este actor lo crea y lo mantiene vivo
// CoopConsole, al que la clave del ini ya redirige:
//     [Engine.Engine] Console=HP1Coop.CoopConsole
// No se toca nada de HarryPotter.u ni de HPBase.u, asi que ninguna de las
// mallas ni texturas incrustadas en esos 14 MB corre peligro.
//
// Una version anterior creaba este actor desde
//     [Engine.GameEngine] ServerActors=HP1Coop.CoopManager
// Se probo y NO funciona: UE1 solo instancia los ServerActors cuando el motor
// arranca como servidor, y HP1 en un jugador es NM_Standalone. Bajo "UCC
// server" si funcionaba, que es lo que hacia el fallo tan confuso.
//
// VARIOS JUGADORES (protocolo 2)
// ------------------------------
// Topologia en estrella: los clientes solo hablan con el host y el host reenvia
// a los demas. Asi solo hace falta abrir un puerto en un router, el del host.
//
// Cada jugador tiene un slot. El 0 es el host; los clientes reciben el suyo en
// el WELCOME y lo escriben en cada paquete que mandan, de forma que todo el
// mundo sabe de quien es cada cosa. El numero de slot que asigna el host es el
// mismo que usa el transporte, asi que no hay dos numeraciones que casar.
//
// Protocolo de texto sobre UDP, delimitado por "|":
//   HPCOOP|2|HELLO|nombre|build                 cliente -> host
//   HPCOOP|2|WELCOME|slot|nombreHost|build      host -> cliente
//   HPCOOP|2|PING|slot|seq   /  PONG|slot|seq
//   HPCOOP|2|S|slot|mapa|x|y|z|yaw|pitch|vx|vy|vz|anim|rate|hp
//   HPCOOP|2|MAP|slot|mapa
//   HPCOOP|2|SP|slot|seq|clase|x|y|z|pitch|yaw   (se manda 3x, dedup por seq)
//   HPCOOP|2|BYE|slot
//
// Los hechizos (SP) ya estan. PICK (objetos) se descarto a proposito: a los
// jugadores les gusta que cada uno tenga sus grageas y cromos. LTRIG resulto
// innecesario - los secretos de Lumos se activan con un spellTrigger, que solo
// reacciona a proyectiles baseSpell, y esos ya se replican.
//================================================================================

class CoopManager extends Actor
  config;

const PROTO = "HPCOOP|2";

// Etiqueta de build. Viaja en HELLO/WELCOME para poder avisar cuando los dos
// jugadores no tienen el mismo mod instalado. Subir esto en cada version que se
// reparta.
const BUILD = "12";

// Jugadores simultaneos, host incluido. Subirlo es cambiar esta constante y los
// tamanos de los arrays (UE1 no acepta constantes como tamano de array). Antes
// de subirlo mucho conviene medir: el host reenvia el trafico de todos a todos,
// asi que el coste crece con el cuadrado de los jugadores.
const MAX_SLOTS = 4;

const SEND_RATE = 0.05;      // 20 Hz
const HELLO_RATE = 1.0;
const PING_RATE = 2.0;
const HIDE_TIMEOUT = 3.0;
const DROP_TIMEOUT = 10.0;

var config string LastHost;
var config int LastPort;
var config string PlayerName;
var config bool bAutoHost;      // hospeda en cuanto carga un nivel
var config bool bAutoConnect;   // llama a LastHost en cuanto carga un nivel
var config bool bShowDebug;
// Re-base vertical del centro del cilindro. Ver CoopPuppet. Ajustable en vivo
// con CoopZ porque depende de origenes de malla horneados en HarryPotter.u.
var config float PuppetZOffset;

var PlayerPawn Player;       // HP1: Harry extends baseHarry extends PlayerPawn
var CoopLink Link;

var bool bConnected;
var bool bIsHost;
var bool bBindFailWarned;   // el aviso de puerto ocupado se da una vez
var bool bWarnedBuild;      // el aviso de version distinta se da una vez
var bool bNoAnswerWarned;   // el aviso de "no contesta nadie" se da una vez
var int  HelloTries;        // saludos enviados sin respuesta
var float LastRecvTime;
var float SendAccum;
var float HelloAccum;
var float PingAccum;
var float FindAccum;
var int RecvCount;
var int SentCount;
var int PingSeq;
var float PingSentAt;
var int EstPingMs;

// Nuestro numero de jugador. 0 = host. -1 = cliente que todavia no ha sido
// admitido, y mientras tanto no manda estado: sin slot no se le podria
// atribuir.
var int MySlot;

// Estado de los demas jugadores, indexado por slot.
// UE1 no admite arrays de bool: se usan bytes (0 = inactivo, 1 = activo).
var byte SlotActive[4];
var string SlotName[4];
var string SlotMap[4];
var vector SlotLoc[4];
var rotator SlotRot[4];
var vector SlotVel[4];
var name SlotAnim[4];
var float SlotAnimRate[4];
var int SlotHealth[4];
var float SlotLastRecv[4];
var int SlotLastSpellSeq[4];
var CoopPuppet Puppets[4];

var string LastAnnouncedMap;

// Sincronizacion de hechizos. NO se engancha Harry.Cast() - eso obligaria a
// inyectar codigo en el paquete del juego. baseWand ya apunta su ultimo disparo
// en LastCastedSpell, asi que detectar un lanzamiento es una comparacion de
// punteros por tick en vez de recorrer actores.
var baseSpell LastSentSpell;
// Un lanzamiento es un evento, no un flujo: si se pierde su paquete el hechizo
// simplemente no aparece. Por eso sale tres veces y el receptor descarta las
// repeticiones por numero de secuencia.
var int SpellSeq;

// ---------------------------------------------------------------------------

event PostBeginPlay()
{
    Super.PostBeginPlay();
    if (PlayerName == "")
        PlayerName = "Harry";
    if (LastPort == 0)
        LastPort = 7777;
    MySlot = -1;
    log("[HP1Coop] manager up on " $ MapName());
    Enable('Tick');
}

// El nombre viaja dentro de un protocolo delimitado por "|", asi que una barra
// en el nombre partiria el paquete y el receptor leeria basura. Se quitan, y se
// recorta para que no desborde el HUD.
function SetPlayerName(string s)
{
    local int i;

    while (true)
    {
        i = InStr(s, "|");
        if (i == -1)
            break;
        s = Left(s, i) $ Mid(s, i + 1);
    }

    if (s == "")
        s = "Harry";
    if (Len(s) > 16)
        s = Left(s, 16);

    PlayerName = s;
    SaveConfig();
    LogMsg("te llamas " $ PlayerName $ " (se lo digo a los demas al saludar)");
}

function LogMsg(coerce string msg)
{
    log("[HP1Coop] " $ msg);
    if (Player != None)
        Player.ClientMessage("[HP1Coop] " $ msg);
}

// El pawn local no existe garantizado cuando se crea este actor, y el juego lo
// cambia durante las cinematicas, asi que se re-adquiere de forma perezosa.
function bool EnsurePlayer()
{
    local PlayerPawn p;

    if (Player != None && !Player.bDeleteMe)
        return true;

    foreach AllActors(class'PlayerPawn', p)
    {
        if (p.Player != None)
        {
            Player = p;
            return true;
        }
    }
    return false;
}

static function int StrSplit(coerce string Text, string delim, out string parts[24])
{
    local int n, i;
    local string rest;

    rest = Text;
    n = 0;
    while (rest != "" && n < 24)
    {
        i = InStr(rest, delim);
        if (i == -1)
        {
            parts[n] = rest;
            n++;
            rest = "";
        }
        else
        {
            parts[n] = Left(rest, i);
            n++;
            rest = Mid(rest, i + Len(delim));
        }
    }
    return n;
}

// ---------------------------------------------------------------------------
// Control de sesion
// ---------------------------------------------------------------------------

// ARREGLO BUG 2 (2026-08-27) - re-hospedar fallaba con "failed to bind UDP
// port 7777".
//
// Antes esto hacia DisconnectLink() (que destruia el socket) y acto seguido
// pedia el MISMO puerto. En UE1 Destroy() solo marca el actor: el socket nativo
// no se cierra hasta la recogida de basura, que dentro de una partida puede
// tardar muchisimo. Y como StartHost pide el puerto exacto (BindPort con
// bUseNextAvailable=False), no se recuperaba solo nunca.
//
// La solucion es no destruir el socket: si ya tenemos uno bindeado al puerto
// que nos piden, se reutiliza y solo se limpia el estado de sesion.
function Host(optional int port)
{
    if (port == 0)
        port = 7777;

    bIsHost = true;
    MySlot = 0;

    if (Link != None && !Link.bDeleteMe && Link.BoundPort == port)
    {
        ResetSession();
        Link.Reset();
        bAutoHost = true;
        bAutoConnect = false;
        LastPort = port;
        SaveConfig();
        LogMsg("hospedando en el puerto UDP " $ port $ ", esperando jugadores...");
        return;
    }

    DisconnectLink();
    bIsHost = true;
    MySlot = 0;

    Link = Spawn(class'CoopLink');
    Link.Init(Self);
    ResetStats();

    if (Link.StartHost(port))
    {
        LastPort = port;
        bAutoHost = true;
        bAutoConnect = false;
        bBindFailWarned = false;
        SaveConfig();
    }
    else
    {
        // Este camino se reintenta cada medio segundo desde Tick, asi que el
        // aviso se da una sola vez: si no, un puerto ocupado llenaria el log y
        // la pantalla de mensajes.
        if (!bBindFailWarned)
        {
            bBindFailWarned = true;
            LogMsg("el puerto " $ port $ " esta ocupado; reintentando en segundo plano...");
        }
        Link.Destroy();
        Link = None;
    }
}

function ConnectTo(string ip, optional int port)
{
    if (port == 0)
        port = 7777;
    DisconnectLink();

    Link = Spawn(class'CoopLink');
    Link.Init(Self);
    bIsHost = false;
    MySlot = -1;             // hasta que el host nos admita
    HelloTries = 0;
    bNoAnswerWarned = false;
    HelloAccum = 0.0;
    ResetStats();

    if (Link.StartClient(ip, port))
    {
        LastHost = ip;
        LastPort = port;
        bAutoConnect = true;
        bAutoHost = false;
        SaveConfig();
        // Llamar ya en vez de esperar un HELLO_RATE entero.
        Link.SendTo(PROTO $ "|HELLO|" $ PlayerName $ "|" $ BUILD);
    }
    else
    {
        Link.Destroy();
        Link = None;
    }
}

// Parte del ARREGLO BUG 2: al desconectar se conserva el socket. Antes se
// destruia, y como UE1 no lo cierra hasta la recogida de basura, el siguiente
// CoopHost no podia volver a coger el puerto.
function DisconnectNow()
{
    if (Link != None)
    {
        if (MySlot >= 0)
            Link.SendTo(PROTO $ "|BYE|" $ MySlot);
        Link.Reset();
    }
    ResetSession();
    bAutoHost = false;
    bAutoConnect = false;
    SaveConfig();
    LogMsg("desconectado");
}

// Limpia el estado de la sesion sin tocar el socket.
function ResetSession()
{
    local int i;

    bConnected = false;
    LastAnnouncedMap = "";
    for (i = 0; i < 4; i++)
        ClearSlot(i);
    ResetStats();
}

// Cierre completo, socket incluido. Se usa al cambiar de puerto y al recoger el
// nivel; para CoopDisconnect basta con ResetSession().
function DisconnectLink()
{
    if (Link != None)
    {
        Link.Destroy();
        Link = None;
    }
    ResetSession();
}

function ClearSlot(int slot)
{
    if (slot < 0 || slot >= 4)
        return;
    SlotActive[slot] = 0;
    SlotName[slot] = "";
    SlotMap[slot] = "";
    SlotLastSpellSeq[slot] = 0;
    HidePuppet(slot);
}

function ResetStats()
{
    RecvCount = 0;
    SentCount = 0;
    EstPingMs = 0;
    PingSeq = 0;
    SpellSeq = 0;
}

// Cuantos jugadores hay aparte de nosotros.
function int PeerCount()
{
    local int i, n;

    for (i = 0; i < 4; i++)
        if (i != MySlot && SlotActive[i] != 0)
            n++;
    return n;
}

function PrintStatus()
{
    local string role;
    local int i;

    if (Link == None)
    {
        LogMsg("sin sesion. Usa CoopHost [puerto] o CoopConnect <ip>[:puerto]");
        return;
    }
    if (bIsHost)
        role = "host";
    else
        role = "cliente";

    LogMsg(role $ ", slot=" $ MySlot $ ", jugadores=" $ (PeerCount() + 1)
         $ ", enviados=" $ SentCount $ ", recibidos=" $ RecvCount
         $ ", ping=" $ EstPingMs $ "ms");

    for (i = 0; i < 4; i++)
    {
        if (i == MySlot || SlotActive[i] == 0)
            continue;
        LogMsg("  [" $ i $ "] " $ SlotName[i] $ " en " $ SlotMap[i]
             $ " (HP " $ SlotHealth[i] $ ")");
    }
}

// Ajuste de altura en vivo: CoopZ <n>. Re-coloca los munecos para que el
// cambio se vea al momento en vez de en el nivel siguiente.
function SetZOffset(float z)
{
    local int i;

    PuppetZOffset = z;
    SaveConfig();
    for (i = 0; i < 4; i++)
    {
        if (Puppets[i] != None && !Puppets[i].bDeleteMe)
        {
            Puppets[i].ZOffset = z;
            Puppets[i].bDidFirstPlace = false;
        }
    }
    LogMsg("altura de los munecos = " $ PuppetZOffset);
}

function ToggleDebug()
{
    bShowDebug = !bShowDebug;
    SaveConfig();
    LogMsg("debug=" $ bShowDebug);
}

// ---------------------------------------------------------------------------
// Paquetes
// ---------------------------------------------------------------------------

// fromSlot es el slot de TRANSPORTE: para el host, en que plaza de su tabla
// esta la direccion que mando el paquete (-1 si es un desconocido). Para el
// cliente siempre 0, porque solo recibe del host.
function OnPacketFrom(string Text, int fromSlot)
{
    local string parts[24];
    local int n, s, seq;
    local float ms;
    local vector SpLoc;
    local rotator SpRot;

    n = StrSplit(Text, "|", parts);
    if (n < 3)
        return;

    // Version del protocolo. Un mod mas viejo habla "HPCOOP|1" y sus paquetes
    // no se pueden interpretar, pero callarse seria el peor de los mundos: el
    // otro veria que no pasa nada y no sabria por que.
    if ((parts[0] $ "|" $ parts[1]) != PROTO)
    {
        if (!bWarnedBuild)
        {
            bWarnedBuild = true;
            LogMsg("AVISO: alguien usa una version incompatible del mod"
                 $ " (protocolo " $ parts[1] $ ", el nuestro es "
                 $ Mid(PROTO, 7) $ "). Instalad todos el mismo HP1Coop.u.");
        }
        return;
    }

    if (bShowDebug && parts[2] != "S")
        LogMsg("recibido: " $ parts[2]);

    LastRecvTime = Level.TimeSeconds;
    RecvCount++;

    // -------------------------------------------------------------- HELLO
    if (parts[2] == "HELLO")
    {
        if (!bIsHost)
            return;                     // solo el host admite jugadores

        // Un jugador que cambia de nivel vuelve con otro puerto de origen, o
        // sea otra direccion, y ocuparia una segunda plaza mientras la vieja
        // caduca. Si ya hay alguien con ese nombre, esa plaza es suya.
        if (n >= 4)
            DropSlotByName(parts[3], fromSlot);

        s = Link.AdoptPending();
        if (s == -1)
        {
            LogMsg("partida llena: " $ parts[3] $ " no cabe");
            return;
        }

        SlotActive[s] = 1;
        SlotLastRecv[s] = Level.TimeSeconds;
        if (n >= 4)
            SlotName[s] = parts[3];
        CheckPeerBuild(n, parts[4], SlotName[s]);

        Link.SendToSlot(s, PROTO $ "|WELCOME|" $ s $ "|" $ PlayerName $ "|" $ BUILD);
        LogMsg(SlotName[s] $ " se ha unido a la partida (slot " $ s $ ")");
        bConnected = true;
        LastAnnouncedMap = "";          // anunciar el mapa al recien llegado
    }
    // ------------------------------------------------------------ WELCOME
    else if (parts[2] == "WELCOME")
    {
        if (bIsHost || n < 4)
            return;

        MySlot = int(parts[3]);
        SlotActive[0] = 1;
        SlotLastRecv[0] = Level.TimeSeconds;
        if (n >= 5)
            SlotName[0] = parts[4];
        CheckPeerBuild(n - 1, parts[5], SlotName[0]);

        bConnected = true;
        LastAnnouncedMap = "";
        LogMsg("conectado a la partida de " $ SlotName[0] $ " como jugador " $ MySlot);
    }
    // --------------------------------------------------------------- PING
    else if (parts[2] == "PING")
    {
        if (n >= 5)
        {
            if (bIsHost)
                Link.SendToSlot(fromSlot, PROTO $ "|PONG|" $ MySlot $ "|" $ parts[4]);
            else
                Link.SendTo(PROTO $ "|PONG|" $ MySlot $ "|" $ parts[4]);
        }
    }
    else if (parts[2] == "PONG")
    {
        if (n >= 5)
        {
            seq = int(parts[4]);
            if (seq == PingSeq && PingSentAt > 0.0)
            {
                ms = (Level.TimeSeconds - PingSentAt) * 1000.0;
                if (EstPingMs == 0)
                    EstPingMs = int(ms);
                else
                    EstPingMs = (EstPingMs * 3 + int(ms)) / 4;
            }
        }
    }
    // ------------------------------------------------------------- ESTADO
    else if (parts[2] == "S")
    {
        if (n < 16)
            return;
        s = int(parts[3]);
        if (s < 0 || s >= 4 || s == MySlot)
            return;

        if (SlotActive[s] == 0)
        {
            SlotActive[s] = 1;
            LogMsg("empieza a llegar el estado del jugador " $ s);
        }
        SlotLastRecv[s] = Level.TimeSeconds;
        SlotMap[s]        = parts[4];
        SlotLoc[s].X      = float(parts[5]);
        SlotLoc[s].Y      = float(parts[6]);
        SlotLoc[s].Z      = float(parts[7]);
        SlotRot[s].Yaw    = int(parts[8]);
        SlotRot[s].Pitch  = int(parts[9]);
        SlotRot[s].Roll   = 0;
        SlotVel[s].X      = float(parts[10]);
        SlotVel[s].Y      = float(parts[11]);
        SlotVel[s].Z      = float(parts[12]);
        SlotAnim[s]       = name(parts[13]);
        SlotAnimRate[s]   = float(parts[14]);
        SlotHealth[s]     = int(parts[15]);
        UpdatePuppet(s);

        Relay(Text, fromSlot);
    }
    // ---------------------------------------------------------------- MAPA
    else if (parts[2] == "MAP")
    {
        if (n < 5)
            return;
        s = int(parts[3]);
        if (s < 0 || s >= 4 || s == MySlot)
            return;

        SlotMap[s] = parts[4];
        LogMsg(SlotName[s] $ " se ha ido a " $ SlotMap[s]);

        // Seguir SOLO al host. Con varios jugadores seguir a cualquiera seria
        // un tira y afloja: dos personas en niveles distintos se arrastrarian
        // la una a la otra sin parar.
        if (!bIsHost && s == 0 && Player != None && SlotMap[0] != MapName())
        {
            LogMsg("siguiendo al host a " $ SlotMap[0]);
            Player.ClientTravel(SlotMap[0], TRAVEL_Absolute, false);
        }

        Relay(Text, fromSlot);
    }
    // ------------------------------------------------------------- HECHIZO
    else if (parts[2] == "SP")
    {
        if (n < 11)
            return;
        s = int(parts[3]);
        if (s < 0 || s >= 4 || s == MySlot)
            return;

        seq = int(parts[4]);
        if (seq <= SlotLastSpellSeq[s])
            return;                     // repeticion de un lanzamiento ya visto
        SlotLastSpellSeq[s] = seq;

        SpLoc.X     = float(parts[6]);
        SpLoc.Y     = float(parts[7]);
        SpLoc.Z     = float(parts[8]);
        SpRot.Pitch = int(parts[9]);
        SpRot.Yaw   = int(parts[10]);
        SpRot.Roll  = 0;
        ApplyRemoteSpell(parts[5], SpLoc, SpRot);

        Relay(Text, fromSlot);
    }
    // ----------------------------------------------------------------- BYE
    else if (parts[2] == "BYE")
    {
        if (n < 4)
            return;
        s = int(parts[3]);
        if (s < 0 || s >= 4 || s == MySlot)
            return;

        LogMsg(SlotName[s] $ " ha dejado la partida");
        ClearSlot(s);
        if (bIsHost)
            Link.FreeSlot(s);
        if (!bIsHost && s == 0)
        {
            // Se fue el host: volver a picar a la puerta.
            bConnected = false;
            MySlot = -1;
            HelloAccum = HELLO_RATE;
        }
        bConnected = (PeerCount() > 0);

        Relay(Text, fromSlot);
    }
}

// El host es el unico camino entre clientes: lo que le llega de uno tiene que
// llegar a los demas, o cada cliente solo veria al host.
function Relay(string Text, int fromSlot)
{
    if (bIsHost && fromSlot > 0)
        Link.SendToAllExcept(fromSlot, Text);
}

// Un jugador que vuelve tras cambiar de nivel llega desde otro puerto, o sea
// otra direccion. Sin esto ocuparia una plaza nueva y la vieja seguiria viva
// hasta caducar, gastando sitio y dejando su muneco plantado.
function DropSlotByName(string nm, int exceptSlot)
{
    local int i;

    if (nm == "")
        return;

    for (i = 1; i < 4; i++)
    {
        if (i != exceptSlot && SlotActive[i] != 0 && SlotName[i] == nm)
        {
            if (bShowDebug)
                LogMsg("liberando la plaza anterior de " $ nm $ " (slot " $ i $ ")");
            ClearSlot(i);
            Link.FreeSlot(i);
        }
    }
}

// Aviso de versiones distintas.
//
// Antes, si dos jugadores tenian builds distintas, se conectaban igual y luego
// pasaban cosas raras sin ningun mensaje: os veiais a medias, o no os veiais, o
// un arreglo estaba en un lado y no en el otro. Era de los fallos mas dificiles
// de diagnosticar porque no parecia un fallo.
//
// El saludo lleva la etiqueta de build. Si no coincide se avisa UNA vez, en
// pantalla y en el log. No se corta la conexion a proposito: puede que la
// diferencia no importe, y decidirlo es cosa de los jugadores.
function CheckPeerBuild(int n, string peerBuild, string who)
{
    if (bWarnedBuild)
        return;

    if (n < 5 || peerBuild == "")
    {
        bWarnedBuild = true;
        LogMsg("AVISO: " $ who $ " usa una version anterior del mod."
             $ " Instalad todos el mismo HP1Coop.u.");
        return;
    }

    if (peerBuild != BUILD)
    {
        bWarnedBuild = true;
        LogMsg("AVISO: versiones distintas - la tuya es la " $ BUILD
             $ " y la de " $ who $ " la " $ peerBuild
             $ ". Instalad todos el mismo HP1Coop.u.");
    }
}

// ---------------------------------------------------------------------------
// Munecos
// ---------------------------------------------------------------------------

function UpdatePuppet(int slot)
{
    if (slot < 0 || slot >= 4 || slot == MySlot)
        return;

    // Solo se refleja a quien esta en nuestro mismo nivel.
    if (SlotMap[slot] != MapName())
    {
        HidePuppet(slot);
        return;
    }
    if (Player == None)
        return;

    // ARREGLO BUG 4 (2026-08-27) - el companero desaparecia para siempre cuando
    // alguien moria, aunque la sesion siguiera viva y los hechizos siguieran
    // llegando (los hechizos no pasan por aqui).
    //
    // La condicion era  Puppet == None.  Si algo destruye el muneco - y la
    // secuencia de muerte de HP1 lo hacia - la referencia NO se queda a None:
    // se queda apuntando a un actor muerto con bDeleteMe. La condicion no se
    // cumplia nunca mas y el muneco no se volvia a crear.
    //
    // Es el mismo patron del bug "zombi" que ya estaba documentado para el
    // manager en la cabecera de esta clase, solo que aqui no se habia aplicado.
    if (Puppets[slot] == None || Puppets[slot].bDeleteMe)
    {
        Puppets[slot] = Spawn(class'CoopPuppet');
        if (Puppets[slot] == None)
        {
            log("[HP1Coop] failed to spawn puppet for slot " $ slot);
            return;
        }
        if (bShowDebug)
            LogMsg("muneco (re)creado para el slot " $ slot);
    }

    // Tiene que estar puesto antes de la primera colocacion, que traza al suelo.
    Puppets[slot].ZOffset = PuppetZOffset;

    if (!Puppets[slot].bDidFirstPlace)
        Puppets[slot].PlaceFirstTime(SlotLoc[slot], SlotRot[slot],
                                     Player.Location, Player.Rotation);

    Puppets[slot].bHidden = false;
    Puppets[slot].SetTarget(SlotLoc[slot], SlotVel[slot], SlotRot[slot],
                            SlotAnim[slot], SlotAnimRate[slot], SlotName[slot]);
}

function HidePuppet(int slot)
{
    if (slot >= 0 && slot < 4 && Puppets[slot] != None && !Puppets[slot].bDeleteMe)
        Puppets[slot].bHidden = true;
}

function HideAllPuppets()
{
    local int i;

    for (i = 0; i < 4; i++)
        HidePuppet(i);
}

// Startup.unr es el menu y Entry.unr el mapa de arranque del motor. Hospedar
// ahi ataria el puerto a un manager que muere en cuanto se carga una partida, y
// entonces el nivel de verdad ya no podria cogerlo.
function bool bIsMenuMap()
{
    local string m;
    m = Caps(MapName());
    return (m == "STARTUP" || m == "ENTRY");
}

// ARREGLO BUG 3 (2026-08-27) - la identidad del nivel.
//
// Level.Outer.Name NO sirve: en HP1 una partida guardada ES un mapa. Cargar
// desde el menu ejecuta literalmente  open save0.usa  (FESlotPage.uc:252), asi
// que el paquete del nivel pasa a llamarse "save0" y los jugadores dejan de
// coincidir en cuanto uno cruza una transicion y el otro no. Observado en
// partida: uno en "save0", el otro en "LEV_TUT1B", y el muneco desaparece.
// Peor aun, la logica de seguimiento intentaba ClientTravel("save0").
//
// El juego si sabe donde esta: HPConsole.doLevelSave saca el nombre real de
// Level.LevelEnterText, cortando en el primer punto (HPConsole.uc:252-256).
// Esa propiedad vive en el LevelInfo, o sea que viaja dentro del savegame y
// sigue siendo correcta despues de cargar. Y es un nombre al que ClientTravel
// puede viajar de verdad, cosa que "save0" no era.
//
// Caps() porque se compara entre maquinas y no queremos que una diferencia de
// mayusculas separe a dos jugadores que estan en el mismo sitio.
function string MapName()
{
    local string s;
    local int n;

    s = Level.LevelEnterText;
    n = InStr(s, ".");
    if (n != -1)
        s = Left(s, n);

    if (s != "")
        return Caps(s);

    return Caps(string(Level.Outer.Name));
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

function DrawHUD(canvas C)
{
    local string S;
    local float XL, YL;
    local int i, shown;

    if (!bConnected)
        return;

    C.DrawColor.R = 255;
    C.DrawColor.G = 255;
    C.DrawColor.B = 255;

    for (i = 0; i < 4; i++)
    {
        if (i == MySlot || SlotActive[i] == 0 || SlotName[i] == "")
            continue;

        S = "Co-op: " $ SlotName[i];
        if (SlotHealth[i] > 0)
            S = S $ " (HP: " $ SlotHealth[i] $ ")";

        C.TextSize(S, XL, YL);
        C.SetPos(10, C.ClipY - YL - 30 - shown * (YL + 2));
        C.DrawText(S, false);
        shown++;
    }
}

// ---------------------------------------------------------------------------

event Tick(float dt)
{
    local string pkt;
    local int i;

    // Re-adquirir el pawn local como mucho dos veces por segundo.
    FindAccum += dt;
    if (FindAccum >= 0.5)
    {
        FindAccum = 0.0;
        if (!EnsurePlayer())
            return;
        if (Link == None && !bIsMenuMap())
        {
            if (bAutoHost)
                Host(LastPort);
            else if (bAutoConnect && LastHost != "")
                ConnectTo(LastHost, LastPort);
        }
    }
    if (Player == None || Link == None)
        return;

    // El cliente sigue picando a la puerta hasta que el host le da un slot.
    if (!bIsHost && MySlot < 0)
    {
        HelloAccum += dt;
        if (HelloAccum >= HELLO_RATE)
        {
            HelloAccum = 0.0;
            HelloTries++;
            if (bShowDebug)
                LogMsg("enviando HELLO a " $ LastHost $ "...");
            Link.SendTo(PROTO $ "|HELLO|" $ PlayerName $ "|" $ BUILD);

            // El aviso de version incompatible que hay en OnPacketFrom solo
            // salta cuando LLEGA un paquete raro. Pero un mod mas viejo tira
            // los nuestros sin contestar, asi que en ese caso - justo cuando
            // mas falta hace - no llegaba nada y no se avisaba de nada. Desde
            // aqui se ve el sintoma que si es visible: llamamos y no contesta
            // nadie.
            if (HelloTries >= 10 && RecvCount == 0 && !bNoAnswerWarned)
            {
                bNoAnswerWarned = true;
                LogMsg("llevo " $ HelloTries $ " intentos con " $ LastHost
                     $ ":" $ LastPort $ " y no contesta nadie.");
                LogMsg("comprueba: que el anfitrion haya escrito CoopHost YA EN"
                     $ " PARTIDA, y que tenga esta misma version del mod"
                     $ " (build " $ BUILD $ ").");
            }
        }
    }

    // Ping. Lo mide el cliente contra el host; al host le basta con el
    // "ultima vez que supe de ti" de cada slot.
    if (bConnected && !bIsHost && MySlot >= 0)
    {
        PingAccum += dt;
        if (PingAccum >= PING_RATE)
        {
            PingAccum = 0.0;
            PingSeq++;
            PingSentAt = Level.TimeSeconds;
            Link.SendTo(PROTO $ "|PING|" $ MySlot $ "|" $ PingSeq);
        }
    }

    // Caducidad por slot. Antes habia un solo temporizador porque solo habia un
    // companero; ahora cada uno cae por su cuenta y los demas siguen jugando.
    for (i = 0; i < 4; i++)
    {
        if (i == MySlot || SlotActive[i] == 0)
            continue;

        if (Level.TimeSeconds - SlotLastRecv[i] > HIDE_TIMEOUT)
            HidePuppet(i);

        if (Level.TimeSeconds - SlotLastRecv[i] > DROP_TIMEOUT)
        {
            LogMsg("se perdio la conexion con " $ SlotName[i]);
            ClearSlot(i);
            if (bIsHost)
                Link.FreeSlot(i);

            if (!bIsHost && i == 0)
            {
                // Cayo el host: pedir plaza otra vez desde cero.
                MySlot = -1;
                bWarnedBuild = false;
                HelloAccum = HELLO_RATE;
                LogMsg("reintentando conectar con " $ LastHost $ ":" $ LastPort $ "...");
            }
        }
    }
    bConnected = (PeerCount() > 0);

    // Sin slot no se manda estado: nadie sabria a quien atribuirlo.
    if (MySlot < 0)
        return;

    // Anunciar el cambio de nivel para que los demas escondan su muneco.
    if (bConnected && MapName() != LastAnnouncedMap)
    {
        LastAnnouncedMap = MapName();
        Link.SendTo(PROTO $ "|MAP|" $ MySlot $ "|" $ LastAnnouncedMap);
    }

    SendAccum += dt;
    if (SendAccum < SEND_RATE)
        return;
    SendAccum = 0.0;

    pkt = PROTO $ "|S|" $ MySlot $ "|" $ MapName()
        $ "|" $ int(Player.Location.X) $ "|" $ int(Player.Location.Y) $ "|" $ int(Player.Location.Z)
        $ "|" $ (Player.Rotation.Yaw & 65535) $ "|" $ Player.Rotation.Pitch
        $ "|" $ int(Player.Velocity.X) $ "|" $ int(Player.Velocity.Y) $ "|" $ int(Player.Velocity.Z)
        $ "|" $ string(Player.AnimSequence) $ "|" $ Player.AnimRate
        $ "|" $ Player.Health;

    Link.SendTo(pkt);
    SentCount++;

    if (bConnected)
        CheckLocalSpell();
}

// ---------------------------------------------------------------------------
// Hechizos
// ---------------------------------------------------------------------------

function CheckLocalSpell()
{
    local baseWand w;
    local baseSpell s;
    local string SpellPkt;

    w = baseWand(Player.Weapon);
    if (w == None)
        return;

    s = w.LastCastedSpell;
    if (s == None || s == LastSentSpell)
        return;

    LastSentSpell = s;

    // BUG 5 (2026-08-27) - Wingardium Leviosa desincronizaba las partidas.
    //
    // Replicar el hechizo funciona porque un hechizo normal es un evento: sale,
    // vuela, choca y explota, y la fisica del juego hace el resto igual en
    // todos los mundos. Leviosa no es un evento, es una manipulacion SOSTENIDA:
    // el hechizo lleva un baseSpell.target (el objeto que levita) y el jugador
    // lo va moviendo con su punteria durante segundos.
    //
    // Nuestra copia nacia sin target, asi que SPELLPostLEV.Tick hacia
    //     rot = rotator(location - target.location)
    // contra None en cada fotograma - 6.081 avisos en una sola partida - y el
    // objeto acababa en un sitio distinto en cada mundo.
    //
    // No se replica. Los demas no veran levitar el objeto, pero cada mundo
    // queda coherente consigo mismo, que es mucho mejor que mundos que
    // discrepan. Sincronizarlo de verdad pide otra cosa: transmitir la posicion
    // del objeto levitado mientras dura, identificandolo por nombre (los mapas
    // son identicos en todas las partidas). Es viable, pero es un flujo
    // continuo, no un evento, y merece su propio trabajo.
    if (IsSustainedSpell(string(s.Class)))
    {
        if (bShowDebug)
            LogMsg("hechizo sostenido no replicado: " $ string(s.Class));
        return;
    }

    SpellSeq++;

    SpellPkt = PROTO $ "|SP|" $ MySlot $ "|" $ SpellSeq $ "|" $ string(s.Class)
        $ "|" $ int(s.Location.X) $ "|" $ int(s.Location.Y) $ "|" $ int(s.Location.Z)
        $ "|" $ s.Rotation.Pitch $ "|" $ (s.Rotation.Yaw & 65535);

    Link.SendTo(SpellPkt);
    Link.SendTo(SpellPkt);
    Link.SendTo(SpellPkt);

    if (bShowDebug)
        LogMsg("hechizo lanzado: " $ string(s.Class));
}

// Un hechizo que necesita un objeto al que agarrarse no se puede recrear como
// proyectil suelto: sin target hace destrozos. Ver BUG 5 en CheckLocalSpell.
//
// La comparacion es por texto y no por clase a proposito: asi vale igual para
// "SPELLPostLEV" que para "HPBase.SPELLPostLEV", que es como puede llegar
// segun quien lo mande.
function bool IsSustainedSpell(string clsName)
{
    local string c;

    c = Caps(clsName);
    return (InStr(c, "SPELLPOSTLEV") != -1 || InStr(c, "SPELLLEV") != -1);
}

// Recrea el proyectil del companero. Se crea sin dueno a proposito: no debe
// atribuirse a nuestro Harry, y nunca debe realimentar CheckLocalSpell, que
// solo lee nuestra propia varita.
function ApplyRemoteSpell(string clsName, vector loc, rotator rot)
{
    local class<baseSpell> c;
    local baseSpell s;

    // Tambien se filtra al recibir: si alguien corre una build anterior seguira
    // mandandolos, y no queremos que su version vieja nos rompa la partida.
    if (IsSustainedSpell(clsName))
        return;

    c = class<baseSpell>(DynamicLoadObject(clsName, class'Class', true));
    if (c == None)
        c = class<baseSpell>(DynamicLoadObject("HPBase." $ clsName, class'Class', true));
    if (c == None)
    {
        log("[HP1Coop] clase de hechizo desconocida: " $ clsName);
        return;
    }

    s = Spawn(c, None, , loc, rot);
    if (s == None)
    {
        if (bShowDebug)
            LogMsg("no se pudo crear el hechizo remoto " $ clsName);
        return;
    }

    s.Velocity = vector(rot) * s.default.Speed;
    if (bShowDebug)
        LogMsg("hechizo remoto: " $ clsName);
}

// ---------------------------------------------------------------------------
// RECONSTRUIDO 2026-08-27. Ver nota en CoopPuppet.uc.
// PuppetZOffset era 12.0 (centro de Harry -> centro de Ron). Con la malla de
// Harry en el muneco ya no hay que re-basar nada: 0.0.
// ---------------------------------------------------------------------------
defaultproperties
{
    PuppetZOffset=0.000000
    bHidden=True
}
