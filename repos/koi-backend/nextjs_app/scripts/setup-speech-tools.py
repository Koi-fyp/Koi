"""Local Windows speech tools only. Downloads official releases; never installs globally."""
import hashlib
import json
import subprocess
import sys
import urllib.request
import venv
import zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'dev/avatar-sandbox/.speech-tools'
VOICE_REVISION = 'c10ece1aade47bb51c153c893d14e5bf8e5b7117'
MODEL_SHA256 = '46d590b90fbb41e4d4f2c54ded44874917f8b11b6e0500de2a89e5d3731b5917'
VOICE_BASE = f'https://huggingface.co/rhasspy/piper-voices/resolve/{VOICE_REVISION}/ur/ur_PK/fasih/medium/'
RHUBARB_URL = 'https://github.com/DanielSWolf/rhubarb-lip-sync/releases/download/v1.14.0/Rhubarb-Lip-Sync-1.14.0-Windows.zip'
def download(url, destination, expected_sha256=None):
    if not destination.exists():
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'KOI-local-speech-setup'}), timeout=120) as response:
            data = response.read()
        if expected_sha256 and hashlib.sha256(data).hexdigest() != expected_sha256: raise RuntimeError('Official model checksum mismatch')
        destination.write_bytes(data)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    if expected_sha256 and digest != expected_sha256: raise RuntimeError('Cached model checksum mismatch')
    return {'url':url,'sha256':digest,'bytes':destination.stat().st_size}
def main():
    if sys.platform != 'win32' or sys.version_info[:2] != (3,14) or sys.maxsize <= 2**32: raise RuntimeError('This pinned tool setup targets Windows x64 only.')
    TOOLS.mkdir(parents=True,exist_ok=True)
    env = TOOLS / 'venv'
    if not (env / 'Scripts/python.exe').exists(): venv.EnvBuilder(with_pip=True).create(env)
    python = env / 'Scripts/python.exe'
    lock = ROOT / 'scripts/speech-requirements.lock.txt'
    packages = ['--require-hashes','-r',str(lock)]
    if not lock.exists(): raise RuntimeError('Pinned wheel lock is required.')
    subprocess.run([str(python),'-m','pip','install','--index-url','https://pypi.org/simple','--only-binary=:all:',*packages],check=True)
    records = {}
    for file in ['ur_PK-fasih-medium.onnx','ur_PK-fasih-medium.onnx.json','MODEL_CARD']:
        records[file]=download(VOICE_BASE+file, TOOLS/file, {'ur_PK-fasih-medium.onnx':MODEL_SHA256,'ur_PK-fasih-medium.onnx.json':'cfcf484a50b4036cb55675b6bbcdb9ddb9061ac10a51cfb2b3ce8391213205ec','MODEL_CARD':'0d6419e74f99fdb0240180fc26067e2f71cff465c61b59e218a7cf53351cf91f'}[file])
    config=json.loads((TOOLS/'ur_PK-fasih-medium.onnx.json').read_text(encoding='utf-8'))
    assert config['audio']['sample_rate']==22050 and config['espeak']['voice']=='ur'
    archive=TOOLS/'Rhubarb-Lip-Sync-1.14.0-Windows.zip'
    records[archive.name]=download(RHUBARB_URL,archive,'62fa416a8d5e382a3828ee4bef358ce520d0b4cabdeaea75a7ac266d098d1fe3')
    with zipfile.ZipFile(archive) as release:
        for entry in release.infolist():
            target=(TOOLS/entry.filename).resolve()
            if not target.is_relative_to(TOOLS.resolve()): raise RuntimeError('Unsafe archive path')
        release.extractall(TOOLS)
    records['PIPER_COPYING']=download('https://raw.githubusercontent.com/OHF-Voice/piper1-gpl/v1.8.0/COPYING',TOOLS/'PIPER_COPYING')
    executable=TOOLS/'Rhubarb-Lip-Sync-1.14.0-Windows/rhubarb.exe'
    version=subprocess.check_output([str(executable),'--version'],text=True).strip()
    assert '1.14.0' in version
    manifest={'piper':'1.8.0','python':sys.version,'rhubarb':version,'voiceRevision':VOICE_REVISION,'downloads':records,
              'rhubarbIntegrity':'Official GitHub HTTPS release; no upstream asset digest published. SHA256 is recorded for local provenance, not an independent signature.'}
    (TOOLS/'install-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(manifest,indent=2))
if __name__=='__main__': main()
