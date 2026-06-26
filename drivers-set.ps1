<#
.SYNOPSIS
    drivers-set — Detecta tu hardware y busca/instala los drivers de Windows.

.DESCRIPTION
    1. Muestra un inventario completo del equipo (procesador, grafica, pantalla,
       red, audio, RAM, placa base).
    2. Escanea dispositivos sin driver o con problemas.
    3. Consulta Windows Update (incluyendo drivers OPCIONALES) por los drivers
       WHQL disponibles: certificados y testeados por Microsoft, los mas
       estables — pensados para no romper Windows.
    4. Te ofrece instalar TODO de una, o elegir cuales.

    Uso (una sola linea en PowerShell):
        irm https://raw.githubusercontent.com/TU_USUARIO/drivers-set/main/drivers-set.ps1 | iex

.NOTES
    Requiere Administrador (se auto-eleva solo). Fuente: Windows Update (WUA).
#>

# ===== CONFIGURACION =========================================================
# URL "raw" del propio script en GitHub. Necesaria para auto-elevarse cuando
# se ejecuta via "irm | iex" (no existe archivo local al cual relanzar).
# >>> CAMBIA esto por tu URL real antes de subirlo a GitHub <<<
$BootstrapUrl = 'https://raw.githubusercontent.com/yokonad/drivers-set/main/drivers-set.ps1'
# =============================================================================

$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'drivers-set' } catch {}

function Write-Titulo($texto) {
    Write-Host ''
    Write-Host "  $texto" -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * $texto.Length)) -ForegroundColor DarkGray
}

function Write-Item($etiqueta, $valor, $color = 'Gray') {
    Write-Host ("    {0,-14}" -f ($etiqueta + ':')) -ForegroundColor DarkGray -NoNewline
    Write-Host " $valor" -ForegroundColor $color
}

# Indicador animado en un runspace aparte (para mostrar progreso mientras la
# busqueda de Windows Update bloquea el hilo principal). Si algo falla, no rompe
# el flujo: simplemente no se ve el spinner.
function Start-Spinner($texto) {
    try {
        $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript({
            param($txt)
            $frames = '|', '/', '-', '\'; $i = 0; $t0 = Get-Date
            while ($true) {
                $seg = [int]((Get-Date) - $t0).TotalSeconds
                [Console]::Write("`r  $($frames[$i % 4]) $txt ($seg s)    ")
                Start-Sleep -Milliseconds 150; $i++
            }
        }).AddArgument($texto)
        [void]$ps.BeginInvoke()
        return [pscustomobject]@{ PS = $ps; RS = $rs }
    } catch {
        Write-Host "  $texto..." -ForegroundColor DarkGray
        return $null
    }
}
function Stop-Spinner($sp) {
    if ($null -eq $sp) { return }
    try { $sp.PS.Stop() } catch {}
    try { $sp.PS.Dispose() } catch {}
    try { $sp.RS.Close(); $sp.RS.Dispose() } catch {}
    try { [Console]::Write("`r" + (' ' * 60) + "`r") } catch {}
}

# ----- 1. Auto-elevacion a Administrador -------------------------------------
$identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identidad)
$esAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $esAdmin) {
    Write-Host ''
    Write-Host '  Se necesitan permisos de Administrador. Solicitando elevacion...' -ForegroundColor Yellow
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-Command', "irm $BootstrapUrl | iex"
        )
    } catch {
        Write-Host '  No se pudo elevar (cancelado por el usuario). Saliendo.' -ForegroundColor Red
    }
    return
}

Clear-Host
Write-Host ''
Write-Host '   ____  ____  _____     _______ ____  ____       ____  _____ _____ ' -ForegroundColor Cyan
Write-Host '  |  _ \|  _ \|_ _\ \   / / ____|  _ \/ ___|     / ___|| ____|_   _|' -ForegroundColor Cyan
Write-Host '  | | | | |_) || | \ \ / /|  _| | |_) \___ \ ____\___ \|  _|   | |  ' -ForegroundColor Cyan
Write-Host '  | |_| |  _ < | |  \ V / | |___|  _ < ___) |____|___) | |___  | |  ' -ForegroundColor Cyan
Write-Host '  |____/|_| \_\___|  \_/  |_____|_| \_\____/     |____/|_____| |_|  ' -ForegroundColor Cyan
Write-Host '        Drivers seguros (WHQL) via Windows Update' -ForegroundColor DarkGray

# ----- 2. Inventario de hardware ---------------------------------------------
Write-Titulo 'Tu equipo'
try {
    $os    = Get-CimInstance Win32_OperatingSystem
    $cs    = Get-CimInstance Win32_ComputerSystem
    $cpu   = Get-CimInstance Win32_Processor | Select-Object -First 1
    $board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
    $gpus  = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name })
    $nics  = @(Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=true' | Where-Object { $_.Name })
    $snds  = @(Get-CimInstance Win32_SoundDevice | Where-Object { $_.Name })

    $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)

    Write-Item 'Equipo'   ("{0} {1}" -f $cs.Manufacturer, $cs.Model) 'White'
    Write-Item 'Windows'  ("{0} ({1})" -f $os.Caption, $os.Version) 'White'
    Write-Item 'Placa'    ("{0} {1}" -f $board.Manufacturer, $board.Product)
    Write-Item 'RAM'      ("$ramGB GB")

    # Procesador + marca
    $marcaCpu = if ($cpu.Name -match 'Intel') { 'Intel' }
                elseif ($cpu.Name -match 'AMD|Ryzen') { 'AMD' } else { 'Otro' }
    Write-Item 'Procesador' ("{0}  ({1} nucleos / {2} hilos) [{3}]" -f `
        $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, $marcaCpu) 'Green'

    # Graficas + marca
    foreach ($g in $gpus) {
        $marcaGpu = if ($g.Name -match 'NVIDIA|GeForce|RTX|GTX') { 'NVIDIA' }
                    elseif ($g.Name -match 'Radeon|AMD') { 'AMD' }
                    elseif ($g.Name -match 'Intel') { 'Intel' } else { 'Otro' }
        Write-Item 'Grafica' ("{0}  (driver {1}) [{2}]" -f $g.Name, $g.DriverVersion, $marcaGpu) 'Green'
    }

    # Pantalla(s)
    try {
        $monitores = @(Get-CimInstance Win32_DesktopMonitor | Where-Object { $_.ScreenWidth })
        foreach ($m in $monitores) {
            Write-Item 'Pantalla' ("{0}x{1}" -f $m.ScreenWidth, $m.ScreenHeight)
        }
    } catch {}

    foreach ($n in $nics) { Write-Item 'Red' $n.Name }
    foreach ($s in $snds) { Write-Item 'Audio' $s.Name }
} catch {
    Write-Host "  No se pudo leer todo el hardware: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ----- 3. Dispositivos con problemas -----------------------------------------
Write-Titulo 'Dispositivos con problemas o sin driver'
try {
    $problemas = @(Get-PnpDevice | Where-Object { $_.Status -ne 'OK' -and $_.Present })
} catch { $problemas = @() }

if ($problemas.Count -gt 0) {
    Write-Host "  $($problemas.Count) dispositivo(s) necesitan atencion:" -ForegroundColor Yellow
    foreach ($d in $problemas) {
        Write-Host ("    - {0}  [{1}]" -f $d.FriendlyName, $d.Status) -ForegroundColor Gray
    }
} else {
    Write-Host '  Todos los dispositivos presentes reportan estado OK.' -ForegroundColor Green
}

# ----- 4a. Paso rapido offline: almacen local de drivers ---------------------
# pnputil /scan-devices hace que Windows instale, sin internet, cualquier driver
# que ya tenga en su almacen local para los dispositivos detectados. Es casi
# instantaneo y resuelve muchos casos antes de ir a la red.
Write-Titulo 'Paso rapido: revisando el almacen local de Windows'
try {
    & pnputil.exe /scan-devices 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  Listo (se instalo lo que ya estaba disponible localmente).' -ForegroundColor Green
    } else {
        Write-Host '  (Omitido: tu version de Windows no soporta este paso.)' -ForegroundColor DarkGray
    }
} catch {
    Write-Host '  (Omitido: tu version de Windows no soporta este paso.)' -ForegroundColor DarkGray
}

# ----- 4b. Busqueda en Windows Update (con caja de velocidad) ----------------
# La lentitud real viene de la busqueda EN LINEA: el agente de Windows Update
# refresca todo el catalogo desde los servidores de Microsoft (minutos).
# La busqueda en CACHE local usa lo ya sincronizado y tarda segundos.
# Por eso la opcion rapida (cache) es la predeterminada.
$sesion = New-Object -ComObject Microsoft.Update.Session

function Buscar-Drivers([bool]$enLinea, [bool]$opcionales) {
    $buscador = $sesion.CreateUpdateSearcher()
    $buscador.Online = $enLinea
    if ($enLinea -and $opcionales) {
        try {
            $msUpdateGuid = '7971f918-a847-4430-9279-4a52d1efe18d'
            $gestor = New-Object -ComObject Microsoft.Update.ServiceManager
            [void]$gestor.AddService2($msUpdateGuid, 7, '')
            $buscador.ServerSelection = 3      # ssOthers
            $buscador.ServiceID = $msUpdateGuid
        } catch {}
    }
    # Solo drivers no instalados. Windows Update solo sirve drivers WHQL.
    # Recorremos la coleccion COM por indice (fiable): asi 0 drivers = 0 reales,
    # y no caemos en el envoltorio que hace que una coleccion vacia parezca 1.
    $coleccion = $buscador.Search("IsInstalled=0 AND Type='Driver'").Updates
    $lista = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $coleccion.Count; $i++) {
        [void]$lista.Add($coleccion.Item($i))
    }
    return , $lista.ToArray()
}

Write-Titulo 'Velocidad de busqueda'
Write-Host '    [1] Rapida   - cache local, segundos (recomendada)' -ForegroundColor Green
Write-Host '    [2] Completa - en linea, mas lenta pero exhaustiva' -ForegroundColor Gray
Write-Host '    [3] Profunda - en linea + opcionales, la mas lenta' -ForegroundColor Gray
$velocidad = (Read-Host '  Elige 1, 2 o 3 (ENTER = 1)').Trim()

switch ($velocidad) {
    '2'     { $enLinea = $true;  $opcionales = $false; $etq = 'Buscando en linea' }
    '3'     { $enLinea = $true;  $opcionales = $true;  $etq = 'Buscando en linea (con opcionales)' }
    default { $enLinea = $false; $opcionales = $false; $etq = 'Buscando en cache local' }
}

$sp1 = Start-Spinner $etq
try {
    $drivers = @(Buscar-Drivers $enLinea $opcionales)
} catch {
    Stop-Spinner $sp1
    Write-Host "  Error consultando Windows Update: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  Revisa tu internet y que el servicio Windows Update este activo.' -ForegroundColor Red
    Read-Host '  Presiona ENTER para salir'
    return
}
Stop-Spinner $sp1

# Si la busqueda rapida (cache) no encontro nada, ofrecer la busqueda en linea.
if ($drivers.Count -eq 0 -and -not $enLinea) {
    Write-Host '  La busqueda rapida no encontro drivers en la cache local.' -ForegroundColor Yellow
    $r = (Read-Host '  Buscar en linea ahora? (mas lento) (S/n)').Trim().ToLower()
    if ($r -notin @('n', 'no')) {
        $sp1b = Start-Spinner 'Buscando en linea'
        try { $drivers = @(Buscar-Drivers $true $false) } catch {}
        Stop-Spinner $sp1b
    }
}

if ($drivers.Count -eq 0) {
    Write-Host ''
    if ($problemas.Count -gt 0) {
        # Hay hardware con problemas pero Windows Update no tiene su driver.
        Write-Host '  Windows Update no tiene drivers para los dispositivos con problemas.' -ForegroundColor Yellow
        Write-Host '  Para esos casos quiza necesites el driver del fabricante (Intel, NVIDIA, etc.).' -ForegroundColor Yellow
    } else {
        Write-Host '  No hay drivers nuevos recomendados. Tu sistema esta al dia. :)' -ForegroundColor Green
    }
    Read-Host '  Presiona ENTER para salir'
    return
}

# ----- 5. Mostrar lista -------------------------------------------------------
Write-Titulo "Drivers disponibles ($($drivers.Count))"
$totalMB = 0
for ($i = 0; $i -lt $drivers.Count; $i++) {
    $u  = $drivers[$i]
    $mb = [math]::Round($u.MaxDownloadSize / 1MB, 1)
    $totalMB += $mb
    Write-Host ("  [{0}] {1}" -f ($i + 1), $u.Title) -ForegroundColor White
    Write-Host ("       Tamano: {0} MB   WHQL/firmado: si" -f $mb) -ForegroundColor DarkGray
}
Write-Host ("`n  Descarga total si instalas todo: {0} MB" -f [math]::Round($totalMB, 1)) -ForegroundColor DarkGray

# ----- 6. Preguntar (ENTER = TODOS) ------------------------------------------
Write-Host ''
Write-Host '  Que deseas instalar?' -ForegroundColor Cyan
Write-Host '    - ENTER  = instalar TODOS (recomendado)' -ForegroundColor Green
Write-Host '    - numeros separados por coma (ej: 1,3,4) = solo esos' -ForegroundColor Gray
Write-Host '    - "no"   = salir sin instalar' -ForegroundColor Gray
$respuesta = (Read-Host '  Tu eleccion').Trim().ToLower()

if ($respuesta -in @('no', 'n', 'salir')) {
    Write-Host '  No se instalo nada. Saliendo.' -ForegroundColor Yellow
    return
}

$aInstalar = New-Object -ComObject Microsoft.Update.UpdateColl
if ([string]::IsNullOrWhiteSpace($respuesta) -or $respuesta -eq 'todos') {
    foreach ($u in $drivers) { [void]$aInstalar.Add($u) }
} else {
    $indices = $respuesta -split ',' | ForEach-Object { $_.Trim() }
    foreach ($idx in $indices) {
        if ($idx -match '^\d+$') {
            $n = [int]$idx - 1
            if ($n -ge 0 -and $n -lt $drivers.Count) {
                [void]$aInstalar.Add($drivers[$n])
            } else {
                Write-Host "  Numero fuera de rango ignorado: $idx" -ForegroundColor Yellow
            }
        }
    }
}

if ($aInstalar.Count -eq 0) {
    Write-Host '  No se selecciono ningun driver valido. Saliendo.' -ForegroundColor Yellow
    return
}

# ----- 7. Descargar e instalar -----------------------------------------------
# Aceptar el contrato de licencia donde aplique (algunos drivers lo exigen,
# si no, la instalacion falla).
foreach ($u in $aInstalar) {
    try { if (-not $u.EulaAccepted) { $u.AcceptEula() } } catch {}
}

Write-Titulo "Descargando $($aInstalar.Count) driver(s)"
$sp2 = Start-Spinner 'Descargando'
try {
    $descargador = $sesion.CreateUpdateDownloader()
    $descargador.Updates = $aInstalar
    [void]$descargador.Download()
    Stop-Spinner $sp2
    Write-Host '  Descarga completada.' -ForegroundColor Green
} catch {
    Stop-Spinner $sp2
    Write-Host "  Error en la descarga: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host '  Presiona ENTER para salir'
    return
}

Write-Titulo 'Instalando drivers'
$sp3 = Start-Spinner 'Instalando'
try {
    $instalador = $sesion.CreateUpdateInstaller()
    $instalador.Updates = $aInstalar
    $res = $instalador.Install()
    Stop-Spinner $sp3
} catch {
    Stop-Spinner $sp3
    Write-Host "  Error en la instalacion: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host '  Presiona ENTER para salir'
    return
}

# ----- 8. Reporte final ------------------------------------------------------
Write-Titulo 'Resultado'
$codigos = @{
    0 = 'No iniciado'; 1 = 'En progreso'; 2 = 'Correcto'
    3 = 'Correcto con errores'; 4 = 'Fallido'; 5 = 'Cancelado'
}
$texto = $codigos[[int]$res.ResultCode]
if ($res.ResultCode -eq 2) {
    Write-Host "  Instalacion: $texto" -ForegroundColor Green
} else {
    Write-Host "  Instalacion: $texto (codigo $($res.ResultCode))" -ForegroundColor Yellow
}

if ($res.RebootRequired) {
    Write-Host ''
    Write-Host '  >>> Es necesario REINICIAR para terminar la instalacion. <<<' -ForegroundColor Yellow
    $r = (Read-Host '  Reiniciar ahora? (s/n)').Trim().ToLower()
    if ($r -in @('s', 'si', 'y')) { Restart-Computer -Force }
}

Write-Host ''
Write-Host '  Listo. Gracias por usar drivers-set.' -ForegroundColor Cyan
Read-Host '  Presiona ENTER para salir'
