import hashlib,json,subprocess,sys,urllib.request,venv
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; TOOLS=ROOT/'dev/avatar-sandbox/.voice-tools'
def main():
 if sys.platform!='win32' or sys.version_info[:2]!=(3,14): raise RuntimeError('Tested setup targets Windows/Python 3.14.')
 TOOLS.mkdir(parents=True,exist_ok=True); env=TOOLS/'venv'
 if not (env/'Scripts/python.exe').exists(): venv.EnvBuilder(with_pip=True).create(env)
 python=env/'Scripts/python.exe';lock=ROOT/'scripts/voice-requirements.lock.txt'
 packages=['--require-hashes','-r',str(lock)]
 if not lock.exists():raise RuntimeError('Pinned voice requirement lock is required.')
 subprocess.run([str(python),'-m','pip','install','--index-url','https://pypi.org/simple','--only-binary=:all:',*packages],check=True)
 records={}
 for name in ['tiny','base']:
  repo='Systran/faster-whisper-'+name
  revision={'tiny':'d90ca5fe260221311c53c58e660288d3deb8d356','base':'ebe41f70d5b6dfa9166e2c581c45c9c0cfc57b66'}[name]
  folder=TOOLS/name;folder.mkdir(exist_ok=True)
  tree=json.load(urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/tree/{revision}?expand=true'))
  records[name]={'repo':repo,'revision':revision,'files':{}}
  for entry in tree:
   file=entry['path']
   if file not in ['config.json','model.bin','tokenizer.json','vocabulary.json','vocabulary.txt','preprocessor_config.json','README.md']: continue
   target=folder/file
   if not target.exists():
    with urllib.request.urlopen(f'https://huggingface.co/{repo}/resolve/{revision}/{file}',timeout=180) as response: target.write_bytes(response.read())
   digest=hashlib.sha256(target.read_bytes()).hexdigest();expected=(entry.get('lfs') or {}).get('oid')
   if expected and expected!=digest: raise RuntimeError('Official ASR model digest mismatch')
   records[name]['files'][file]={'bytes':target.stat().st_size,'sha256':digest,'upstreamLfsSha256':expected}
 (TOOLS/'models.json').write_text(json.dumps(records,indent=2),encoding='utf-8');print(json.dumps(records,indent=2))
if __name__=='__main__': main()
