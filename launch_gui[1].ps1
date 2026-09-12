[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $DllPath
)

$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $invocationPath = $MyInvocation.MyCommand.Path
    if (-not [string]::IsNullOrWhiteSpace($invocationPath)) {
        $scriptRoot = Split-Path -Parent $invocationPath
    }
}
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($DllPath)) {
    $DllPath = Join-Path -Path $scriptRoot -ChildPath 'robloxplayerbeta.dll'
} elseif (-not [IO.Path]::IsPathRooted($DllPath)) {
    $DllPath = Join-Path -Path $scriptRoot -ChildPath $DllPath
}

$resolvedDll = (Resolve-Path -LiteralPath $DllPath -ErrorAction Stop).Path

if (-not ('LuminGui.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace LuminGui {
    public static class NativeMethods {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr LoadLibrary(string fileName);

        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
        public static extern IntPtr GetProcAddress(IntPtr module, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool FreeLibrary(IntPtr module);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        public delegate int GuiFunction();
    }
}
'@
}

$module = [LuminGui.NativeMethods]::LoadLibrary($resolvedDll)
if ($module -eq [IntPtr]::Zero) {
    $error = [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    throw "No se pudo cargar la DLL '$resolvedDll': $($error.Message)"
}

try {
    $stopAddress = [IntPtr]::Zero
    $stop = $null
    $launchAddress = [LuminGui.NativeMethods]::GetProcAddress($module, 'LaunchGui')
    $stopAddress = [LuminGui.NativeMethods]::GetProcAddress($module, 'StopGui')
    $runningAddress = [LuminGui.NativeMethods]::GetProcAddress($module, 'IsGuiRunning')

    if ($launchAddress -eq [IntPtr]::Zero -or $stopAddress -eq [IntPtr]::Zero -or $runningAddress -eq [IntPtr]::Zero) {
        throw 'La DLL no contiene las exportaciones LaunchGui, StopGui e IsGuiRunning.'
    }

    $launch = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($launchAddress, [LuminGui.NativeMethods+GuiFunction])
    $stop = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($stopAddress, [LuminGui.NativeMethods+GuiFunction])
    $isRunning = [Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($runningAddress, [LuminGui.NativeMethods+GuiFunction])

    if ($launch.Invoke() -eq 0) {
        $error = [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        throw "La DLL se cargó, pero no pudo iniciar la GUI: $($error.Message)"
    }

    Write-Host 'EZ4STRAP ULTRA iniciado desde la DLL. Cierra la ventana para terminar.' -ForegroundColor Green
    while ($isRunning.Invoke() -ne 0) {
        Start-Sleep -Milliseconds 250
    }
}
finally {
    if ($null -ne $stop -and $stopAddress -ne [IntPtr]::Zero) {
        try { [void]$stop.Invoke() } catch { }
    }
    [void][LuminGui.NativeMethods]::FreeLibrary($module)
}
