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
$BootstrapUrl = 'https://raw.githubusercontent.com/TU_USUARIO/drivers-set/main/drivers-set.ps1'
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

# ----- 4. Registrar Microsoft Update (para drivers OPCIONALES) ---------------
Write-Titulo 'Buscando drivers en Windows Update (puede tardar)'
$idServicio = $null
try {
    # GUID del servicio Microsoft Update: incluye drivers opcionales/extra.
    $msUpdateGuid = '7971f918-a847-4430-9279-4a52d1efe18d'
    $gestor = New-Object -ComObject Microsoft.Update.ServiceManager
    [void]$gestor.AddService2($msUpdateGuid, 7, '')
    $idServicio = $msUpdateGuid
} catch {
    # Si falla, seguimos con el servicio por defecto de Windows Update.
    $idServicio = $null
}

try {
    $sesion   = New-Object -ComObject Microsoft.Update.Session
    $buscador = $sesion.CreateUpdateSearcher()
    $buscador.Online = $true
    if ($idServicio) {
        $buscador.ServerSelection = 3          # ssOthers
        $buscador.ServiceID = $idServicio
    }
    # Solo drivers no instalados. Windows Update solo sirve drivers WHQL.
    $resultado = $buscador.Search("IsInstalled=0 AND Type='Driver'")
    $drivers   = @($resultado.Updates)
} catch {
    Write-Host "  Error consultando Windows Update: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  Revisa tu internet y que el servicio Windows Update este activo.' -ForegroundColor Red
    Read-Host '  Presiona ENTER para salir'
    return
}

if ($drivers.Count -eq 0) {
    Write-Host ''
    Write-Host '  No hay drivers nuevos recomendados. Tu sistema esta al dia. :)' -ForegroundColor Green
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
Write-Titulo "Descargando $($aInstalar.Count) driver(s)"
try {
    $descargador = $sesion.CreateUpdateDownloader()
    $descargador.Updates = $aInstalar
    [void]$descargador.Download()
    Write-Host '  Descarga completada.' -ForegroundColor Green
} catch {
    Write-Host "  Error en la descarga: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host '  Presiona ENTER para salir'
    return
}

Write-Titulo 'Instalando drivers'
try {
    $instalador = $sesion.CreateUpdateInstaller()
    $instalador.Updates = $aInstalar
    $res = $instalador.Install()
} catch {
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
