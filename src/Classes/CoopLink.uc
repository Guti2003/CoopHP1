//================================================================================
// HP1 Co-op  -  modo cooperativo para Harry Potter y la Piedra Filosofal (2001)
// Miguel Gutierrez (@Guti2003). Todos los derechos reservados - ver LICENSE.
//================================================================================
// CoopLink - UDP socket wrapper for the HP1 co-op mod.
//
// Topologia en ESTRELLA. Los clientes solo hablan con el host; el host reenvia
// a los demas. Se eligio asi para que siga haciendo falta abrir un solo puerto
// en un solo router - el del host - igual que cuando el mod era de dos.
//
// La tabla de direcciones vive aqui y no en CoopManager a proposito: IpAddr es
// un struct de IpDrv y solo las clases que descienden de InternetLink lo
// conocen. Fuera se trabaja con numeros de slot.
//
// El slot 0 es siempre el host. Los clientes ocupan del 1 en adelante, y el
// numero que el host les asigna es el mismo que usan luego dentro de cada
// paquete, asi que slot de transporte y slot logico coinciden.
//
// Ported from HP2Coop (MIT, jenyaalexanov). El envoltorio de socket es suyo;
// la tabla de peers y el reenvio son de esta version.
//================================================================================

class CoopLink extends UdpLink;

var CoopManager mgr;

// Cliente: direccion del host. Host: no se usa.
var IpAddr RemoteAddr;
var bool bRemoteKnown;

var int BoundPort;      // puerto realmente bindeado; 0 = sin socket

// Host: direcciones de los clientes, indexadas por slot. El 0 queda libre
// porque es el propio host y no se manda paquetes a si mismo.
var IpAddr SlotAddr[4];
// UE1 no admite arrays de bool: se usan bytes (0 libre, 1 ocupado).
var byte   SlotUsed[4];

// Direccion del paquete que se esta procesando ahora mismo. Sirve para que el
// manager pueda dar de alta a un desconocido al recibir su HELLO, sin que
// IpAddr salga de esta clase.
var IpAddr PendingAddr;

function Init(CoopManager m)
{
    mgr = m;
    ReceiveMode = RMODE_Event;
    LinkMode = MODE_Text;
}

function bool StartHost(int port)
{
    local int bound;
    local int i;

    bRemoteKnown = false;
    for (i = 0; i < 4; i++)
        SlotUsed[i] = 0;

    bound = BindPort(port, false);
    if (bound == 0)
    {
        mgr.LogMsg("failed to bind UDP port "$port);
        return false;
    }
    BoundPort = bound;
    mgr.LogMsg("hosting on UDP port "$bound$", waiting for players...");
    return true;
}

function bool StartClient(string ip, int port)
{
    local int bound;

    if (!StringToIpAddr(ip, RemoteAddr))
    {
        mgr.LogMsg("bad IP address: "$ip$" (use numeric form, e.g. 192.168.1.5)");
        return false;
    }
    RemoteAddr.Port = port;
    bRemoteKnown = true;

    bound = BindPort(0, true);
    if (bound == 0)
    {
        mgr.LogMsg("failed to bind a local UDP port");
        return false;
    }
    BoundPort = bound;
    mgr.LogMsg("connecting to "$ip$":"$port$" (local port "$bound$")...");
    return true;
}

// ---------------------------------------------------------------------------
// Envio
// ---------------------------------------------------------------------------

// Cliente: al host. Host: a todos sus clientes.
function SendTo(coerce string s)
{
    local int i;

    if (mgr != None && mgr.bIsHost)
    {
        for (i = 1; i < 4; i++)
            if (SlotUsed[i] != 0)
                SendText(SlotAddr[i], s);
        return;
    }

    if (bRemoteKnown)
        SendText(RemoteAddr, s);
}

function SendToSlot(int slot, coerce string s)
{
    if (slot <= 0 || slot >= 4)
    {
        // El slot 0 es el host: si somos cliente, "mandar al slot 0" es
        // mandar al host por su direccion conocida.
        if (slot == 0 && !mgr.bIsHost && bRemoteKnown)
            SendText(RemoteAddr, s);
        return;
    }
    if (SlotUsed[slot] != 0)
        SendText(SlotAddr[slot], s);
}

// Reenvio del host: todos menos quien lo mando.
function SendToAllExcept(int slot, coerce string s)
{
    local int i;

    for (i = 1; i < 4; i++)
        if (SlotUsed[i] != 0 && i != slot)
            SendText(SlotAddr[i], s);
}

// ---------------------------------------------------------------------------
// Tabla de clientes (solo la usa el host)
// ---------------------------------------------------------------------------

function int FindSlot(IpAddr a)
{
    local int i;

    for (i = 1; i < 4; i++)
        if (SlotUsed[i] != 0 && SlotAddr[i].Addr == a.Addr && SlotAddr[i].Port == a.Port)
            return i;
    return -1;
}

// Da de alta la direccion del paquete que se esta procesando. Devuelve el slot,
// o -1 si ya no caben mas jugadores.
function int AdoptPending()
{
    local int i;

    i = FindSlot(PendingAddr);
    if (i != -1)
        return i;

    for (i = 1; i < 4; i++)
    {
        if (SlotUsed[i] == 0)
        {
            SlotUsed[i] = 1;
            SlotAddr[i] = PendingAddr;
            return i;
        }
    }
    return -1;
}

function FreeSlot(int slot)
{
    if (slot > 0 && slot < 4)
        SlotUsed[slot] = 0;
}

function string SlotAddrString(int slot)
{
    if (slot > 0 && slot < 4 && SlotUsed[slot] != 0)
        return IpAddrToString(SlotAddr[slot]);
    return "";
}

function int CountPeers()
{
    local int i, n;

    for (i = 1; i < 4; i++)
        if (SlotUsed[i] != 0)
            n++;
    return n;
}

// Olvida a los peers pero conserva el socket abierto. Ver ARREGLO BUG 2 en
// CoopManager.Host().
function Reset()
{
    local int i;

    bRemoteKnown = false;
    for (i = 0; i < 4; i++)
        SlotUsed[i] = 0;
}

// ---------------------------------------------------------------------------

event ReceivedText(IpAddr Addr, string Text)
{
    local int slot;

    // Ignorar cualquier cosa que no sea del mod.
    if (Left(Text, 7) != "HPCOOP|")
        return;

    PendingAddr = Addr;

    if (mgr == None)
        return;

    if (mgr.bIsHost)
    {
        // El alta la decide el manager al ver un HELLO, no aqui: asi un paquete
        // suelto de alguien que no viene a jugar no ocupa una plaza.
        slot = FindSlot(Addr);
        mgr.OnPacketFrom(Text, slot);
        return;
    }

    // Cliente: el host re-crea su socket en cada cambio de nivel, asi que su
    // puerto de origen cambia. Seguir siempre la ultima direccion vista.
    RemoteAddr = Addr;
    bRemoteKnown = true;
    mgr.OnPacketFrom(Text, 0);
}

event Destroyed()
{
    BoundPort = 0;
    mgr = None;
    Super.Destroyed();
}

defaultproperties
{
}
