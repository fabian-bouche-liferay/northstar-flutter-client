# Starts the Android emulator `nmg_pixel` with both QR scan simulations:
#   - back camera  -> build/camera/feed.png (written by tool/simulate_scan.dart)
#   - front camera -> a PC webcam (list them: emulator -webcam-list)
# In the app, long-press the home title to pick the camera the scanner uses.
#
#   powershell -File tool/emulator.ps1                    # front = webcam1
#   powershell -File tool/emulator.ps1 -Webcam webcam0    # another webcam
#   powershell -File tool/emulator.ps1 -Webcam emulated   # no webcam at all
param([string]$Webcam = "webcam1")

$sdk = "$env:USERPROFILE\Android\Sdk"
$feed = Join-Path $PSScriptRoot "..\build\camera\feed.png"
if (-not (Test-Path $feed)) { & dart run tool/simulate_scan.dart --blank }
& "$sdk\emulator\emulator.exe" -avd nmg_pixel -no-boot-anim `
    -camera-back "imagefile:$(Resolve-Path $feed)" `
    -camera-front $Webcam
