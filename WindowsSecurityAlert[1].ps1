param([switch]$Stop)

 $ErrorActionPreference = 'SilentlyContinue'
 $NombreApp = 'WindowsSecurityAlert'
 $LogPath   = Join-Path $env:USERPROFILE 'WindowsSecurityAlert.log'
 $RutaIni   = Join-Path $PSScriptRoot "$NombreApp.ini"
 $script:StopFlag = Join-Path $env:TEMP 'WindowsSecurityAlert.stop.flag'


 Remove-Item -LiteralPath $script:StopFlag -Force -ErrorAction SilentlyContinue


function Write-BlockLog([string]$M) {
    try { Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format s)  $M" -ErrorAction Stop } catch {}
}


function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Stop -and -not (Test-Admin)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}


if ($Stop) {
    try { New-Item -ItemType File -Force -Path $script:StopFlag | Out-Null } catch {}
    $cont = 0
    Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" | ForEach-Object {
        if ($_.CommandLine -and $_.CommandLine -like "*$NombreApp.ps1*" -and $_.ProcessId -ne $PID) {
            Stop-Process -Id $_.ProcessId -Force
            $cont++
        }
    }
    Write-Host "[+] Servicio de seguridad detenido. ($cont instancias cerradas)"
    exit
}


 $script:MensajeVirus = 'No se pudo completar la operacion porque el archivo contiene un virus o software potencialmente no deseado.'
 $script:Nombres   = @('D', 'D.exe')
 $script:Patrones  = @('detect-*', 'detect*.exe')
 $script:Carpetas  = @((Join-Path $env:USERPROFILE 'Downloads\aura'))
 $script:Hash      = '147DF37C7F85F59FE440B4FB98D3898A8AA6B3359F4D60093CF2583E726FADCB'
 $script:Cooldown  = 5

if (Test-Path $RutaIni) {
    $seccion = ''
    foreach ($linea in [IO.File]::ReadAllLines($RutaIni)) {
        $l = $linea.Trim()
        if ($l -match '^\[(.+)\]$') { $seccion = $Matches[1]; continue }
        if ($l -match '^;' -or $l -eq '') { continue }

        if ($seccion -eq 'General' -and $l -match '^(Mensaje|Hash|Cooldown)\s*=\s*(.*)$') {
            switch ($Matches[1]) {
                'Mensaje'  { $script:MensajeVirus = $Matches[2].Trim() }
                'Hash'     { $script:Hash = $Matches[2].Trim().ToUpper() }
                'Cooldown' { $script:Cooldown = [int]$Matches[2].Trim() }
            }
        }
        if ($seccion -eq 'Objetivos' -and $l -match '^(Nombre|Patron|Carpeta)(\d+)\s*=\s*(.*)$') {
            $tipo = $Matches[1]
            $val  = $Matches[3].Trim()
            if ($val) {
                switch ($tipo) {
                    'Nombre'  { $script:Nombres += $val }
                    'Patron'  { $script:Patrones += $val }
                    'Carpeta' {
                        $exp = [Environment]::ExpandEnvironmentVariables($val)
                        if (-not $exp.EndsWith('\')) { $exp += '\' }
                        $script:Carpetas += $exp
                    }
                }
            }
        }
    }
}


 $popupScript = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NativeMsg {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);
}
"@
[NativeMsg]::MessageBox([IntPtr]::Zero, '__MENSAJE__', '__TITULO__', 0x50010) | Out-Null
'@

function Start-VirusDialog([string]$ProcessName) {
    try {
        $final = $popupScript.Replace('__TITULO__', 'Seguridad de Windows')
        $final = $final.Replace('__MENSAJE__', $script:MensajeVirus)
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($final)
        $enc = [Convert]::ToBase64String($bytes)
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -EncodedCommand $enc"
    } catch {
        Write-BlockLog "Fallo el aviso: $($_.Exception.Message)"
    }
}


 $yaProcesados = @{}
 $ultimoAviso = @{}

function Invoke-Bloqueo($Proceso) {
    $nombre = [string]$Proceso.Name
    $ruta   = [string]$Proceso.ExecutablePath
    $pid    = [int]$Proceso.ProcessId

    # 1) Matar PRIMERO (agresivo, con arbol de hijos)
    $muerto = $false
    try {
        Stop-Process -Id $pid -Force -ErrorAction Stop
        $muerto = $true
    } catch {
        taskkill.exe /F /T /PID $pid 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $muerto = $true }
    }

    # 2) DESPUES sale el aviso (cooldown por nombre: no repetir en avalancha)
    $ahora = Get-Date
    if (-not ($ultimoAviso.ContainsKey($nombre) -and (($ahora - $ultimoAviso[$nombre]).TotalSeconds -lt $script:Cooldown))) {
        $ultimoAviso[$nombre] = $ahora
        Start-VirusDialog -ProcessName $nombre
    }

    # 3) Log en formato Windows Defender
    if ($muerto) {
        Write-BlockLog "Windows Defender Antivirus ha detectado y bloqueado una amenaza."
        Write-BlockLog "  Amenaza:         $nombre"
        Write-BlockLog "  Ruta:            $ruta"
        Write-BlockLog "  PID:             $pid"
        Write-BlockLog "  Nivel de alerta: Grave"
        Write-BlockLog "  Categoria:       Trojan:Win32/Wacatac.B!ml"
        Write-BlockLog "  Accion:          Bloquear y quitar"
        Write-BlockLog "  Estado:          Eliminado"
    } else {
        Write-BlockLog "Windows Defender Antivirus: no se pudo bloquear $nombre (PID $pid)."
    }
}


Write-Host "================================================="
Write-Host " Proteccion contra virus y amenazas - ACTIVA"
Write-Host "================================================="
Write-Host ""
Write-Host " Vigilando:"
Write-Host "   Nombres:   $($script:Nombres -join ', ')"
Write-Host "   Patrones:  $($script:Patrones -join ', ')"
Write-Host "   Carpetas:  $($script:Carpetas -join ', ')"
if ($script:Hash) { Write-Host "   Hash:      $($script:Hash.Substring(0,16))..." }
Write-Host ""
Write-Host " Log: $LogPath"
Write-Host ""
Write-Host " PARA DETENER:"
Write-Host "   - Ctrl+C en esta ventana"
Write-Host "   - Cerrar esta ventana"
Write-Host "   - Otra consola: .\$NombreApp.ps1 -Stop"
Write-Host "-------------------------------------------------"
Write-Host " Vigilando... (mata al objetivo y despues muestra el aviso)"
Write-Host "-------------------------------------------------"


 $creado = $false
 $mtx = New-Object System.Threading.Mutex($true, "Global\WindowsSecurityAlert_Activo", [ref]$creado)
if (-not $creado) {
    $mtx.Dispose()
    Write-Host "[!] Ya hay una instancia corriendo. Usa -Stop para detenerla."
    exit
}


try {
    while ($true) {
        if (Test-Path -LiteralPath $script:StopFlag) { break }
        $todos = Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue

        foreach ($proc in $todos) {
            $esObjetivo = $false
            $nombre = [string]$proc.Name
            $ruta   = [string]$proc.ExecutablePath


            foreach ($n in $script:Nombres) {
                if ($nombre -ieq $n) { $esObjetivo = $true; break }
            }


            if (-not $esObjetivo) {
                foreach ($p in $script:Patrones) {
                    if ($nombre -like $p) { $esObjetivo = $true; break }
                }
            }


            if (-not $esObjetivo -and $ruta) {
                foreach ($c in $script:Carpetas) {
                    if ($ruta.StartsWith($c, [StringComparison]::OrdinalIgnoreCase)) { $esObjetivo = $true; break }
                }
            }


            if (-not $esObjetivo -and $ruta -and (Test-Path -LiteralPath $ruta -PathType Leaf)) {
                if ([IO.Path]::GetExtension($ruta) -ieq '.exe') {
                    $hashActual = (Get-FileHash -LiteralPath $ruta -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                    if ($hashActual -eq $script:Hash) { $esObjetivo = $true }
                }
            }

            if ($esObjetivo -and -not $yaProcesados.ContainsKey($proc.ProcessId)) {
                $yaProcesados[$proc.ProcessId] = $true
                Invoke-Bloqueo -Proceso $proc
            }
        }


        foreach ($k in @($yaProcesados.Keys)) {
            if (-not (Get-Process -Id $k -ErrorAction SilentlyContinue)) {
                $yaProcesados.Remove($k)
            }
        }

        Start-Sleep -Milliseconds 200
    }
}
finally {
    Remove-Item -LiteralPath $script:StopFlag -Force -ErrorAction SilentlyContinue
    $mtx.ReleaseMutex()
    $mtx.Dispose()
    Write-BlockLog 'Proteccion en tiempo real detenida por el usuario.'
    Write-Host ""
    Write-Host "[+] Vigilancia detenida."
}