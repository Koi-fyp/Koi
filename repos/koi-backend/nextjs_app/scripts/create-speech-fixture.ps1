# Local development only. No downloads, recordings or online synthesis.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$fixtureDir = Join-Path $PSScriptRoot '../dev/avatar-sandbox/.fixtures'
New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
  $synth.SelectVoice('Microsoft David Desktop')
  $synth.Rate = 0
  $format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
  $segments = @('Ah.', 'Ee.', 'Oh.', 'Ooh.', 'Hello. I am Koi.')
  for ($i = 0; $i -lt $segments.Length; $i++) {
    $synth.SetOutputToWaveFile((Join-Path $fixtureDir "segment-$i.wav"), $format)
    $synth.Speak($segments[$i])
    $synth.SetOutputToNull()
  }
} finally { $synth.Dispose() }
python (Join-Path $PSScriptRoot 'assemble-speech-fixture.py')
if ($LASTEXITCODE -ne 0) { throw 'Fixture assembly failed.' }
