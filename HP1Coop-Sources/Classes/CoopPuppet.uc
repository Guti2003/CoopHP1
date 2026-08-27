class CoopPuppet extends Pawn;

const SIDE_OFFSET = 80.0;
const HARRY_HEIGHT = 42.0;   // Harry.uc defaultproperties CollisionHeight

var float ZOffset;           // peer centre -> puppet centre; set by CoopManager

var vector TargetLoc;
var vector TargetVel;
var rotator TargetRot;
var name TargetAnim;
var float TargetAnimRate;
var string PlayerName;
var float LastPacketAge;
var bool bDidFirstPlace;

event PostBeginPlay()
{
    Super.PostBeginPlay();
    DisableCollision();
}

function DisableCollision()
{
    SetCollision(False, False, False);
    bProjTarget = False;
}

// Peer sends Harry's Location, which is his collision cylinder centre.
// Re-base it onto Ron's centre.
function vector PeerToLocal(vector peerMid)
{
    local vector v;
    v = peerMid;
    v.Z = peerMid.Z - ZOffset;
    return v;
}

// Height at which the puppet's centre must sit for its feet to rest on floorZ.
function float FloorToCentre(float floorZ)
{
    return floorZ + HARRY_HEIGHT - ZOffset;
}

function SetTarget(vector L, vector V, rotator R, name Anim, float AnimRate, string Name)
{
    TargetLoc = PeerToLocal(L);
    TargetVel = V;
    TargetRot = R;
    TargetAnim = Anim;
    TargetAnimRate = AnimRate;
    PlayerName = Name;
    LastPacketAge = 0.0;
}

// Trace world geometry under XY; returns a centre-height Location standing on
// whatever floor is below 'at'.
function vector SnapFeetToFloor(vector at)
{
    local vector HitLoc, HitNorm, start, end;
    local Actor HitAct;

    start = at;
    start.Z = at.Z + 250.0;
    end = at;
    end.Z = at.Z - 1000.0;

    HitAct = Trace(HitLoc, HitNorm, end, start, false);
    if (HitAct != None)
    {
        HitLoc.Z = FloorToCentre(HitLoc.Z);
        return HitLoc;
    }

    at.Z = at.Z - ZOffset;
    return at;
}

// One-shot: place beside the local player, then snap to the real floor.
function PlaceFirstTime(vector remoteLoc, rotator remoteRot, vector localLoc, rotator localRot)
{
    local vector flat, dir, p;
    local int attempt;
    local rotator tryRot;

    DisableCollision();

    flat = remoteLoc - localLoc;
    flat.Z = 0;
    if (VSize(flat) > 40.0)
        dir = Normal(flat);
    else
        dir = Normal(vect(0,1,0) << localRot);

    p = SnapFeetToFloor(localLoc + dir * SIDE_OFFSET);
    for (attempt = 1; attempt <= 3; attempt++)
    {
        if (Abs(p.Z - (localLoc.Z - ZOffset)) < 80.0)
            break;
        tryRot.Yaw = localRot.Yaw + attempt * 16384;
        dir = Normal(vect(0,1,0) << tryRot);
        p = SnapFeetToFloor(localLoc + dir * SIDE_OFFSET);
    }

    SetLocation(p);
    remoteRot.Pitch = 0;
    remoteRot.Roll = 0;
    SetRotation(remoteRot);
    TargetLoc = PeerToLocal(remoteLoc);
    bDidFirstPlace = true;
    bHidden = false;
}

simulated event Tick(float dt)
{
    local vector desired, d;
    local int yawDiff;
    local rotator newRot;
    local float blend;

    // Pawn base may flip collision back on.
    if (bCollideActors || bBlockActors || bBlockPlayers)
        DisableCollision();

    LastPacketAge += dt;

    // Dead reckoning: extrapolate for a quarter second, then freeze.
    if (LastPacketAge < 0.25)
        desired = TargetLoc + TargetVel * LastPacketAge;
    else
        desired = TargetLoc;

    blend = FClamp(dt * 14.0, 0.0, 1.0);

    d = desired - Location;
    if (VSize(d) > 800.0)
        SetLocation(desired);          // teleport / big desync
    else if (VSize(d) > 1.0)
        SetLocation(Location + d * blend);

    yawDiff = (TargetRot.Yaw - Rotation.Yaw) & 65535;
    if (yawDiff > 32768)
        yawDiff -= 65536;
    newRot = Rotation;
    newRot.Yaw = (Rotation.Yaw + int(float(yawDiff) * blend)) & 65535;
    newRot.Pitch = 0;
    newRot.Roll = 0;
    SetRotation(newRot);

    if (TargetAnim != '' && AnimSequence != TargetAnim)
        PlayAnim(TargetAnim, TargetAnimRate, 0.15);
    else if (bAnimFinished && TargetAnim != '' && TargetAnimRate > 0)
        PlayAnim(TargetAnim, TargetAnimRate, 0.0);
}

// ---------------------------------------------------------------------------
// RECONSTRUIDO 2026-08-27. UE1 no guarda defaultproperties en el ScriptText del
// .u, asi que este bloque no se recupero: esta deducido del codigo, de los
// comentarios de cabecera y de la tabla de nombres del paquete.
//
// ARREGLO BUG 1 - la malla era SkeletalMesh'HarryPotter.skronMesh'.
// skronMesh NO contiene el set de animaciones de Harry, y como el emisor manda
// nombres de animacion de Harry, PlayAnim fallaba en cada tick y el muneco se
// veia congelado (21.352 lineas de error en una sola sesion). Verificado:
// skharryMesh existe en HarryPotter.u y contiene breath, Jump, climb32,
// climb96start, climb96end y runback, que son justo las que faltaban.
// Coste aceptado por Miguel: se ven dos Harrys.
//
// OJO - con la malla de Harry el re-basado de altura sobra: el peer manda el
// centro del cilindro de Harry y el muneco YA es Harry. PuppetZOffset pasa a
// 0.0 en CoopManager. Si tu config guardada trae 12, corrigelo con  CoopZ 0
// ---------------------------------------------------------------------------
defaultproperties
{
    DrawType=DT_Mesh
    Mesh=SkeletalMesh'HarryPotter.skharryMesh'
    bHidden=True
    bCollideActors=False
    bBlockActors=False
    bBlockPlayers=False
    bProjTarget=False
    CollisionRadius=17.000000
    CollisionHeight=42.000000
    Role=ROLE_Authority
    RemoteRole=ROLE_None
}
