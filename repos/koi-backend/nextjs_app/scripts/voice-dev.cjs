const path=require('node:path'),{spawn}=require('node:child_process');
if(process.env.NODE_ENV && process.env.NODE_ENV!=='development')throw new Error('Voice worker is development-only.');
const root=path.resolve(__dirname,'..');const child=spawn(path.join(root,'dev/avatar-sandbox/.voice-tools/venv/Scripts/python.exe'),['-X','utf8',path.join(root,'dev/avatar-sandbox/voice_service.py')],{cwd:root,stdio:'inherit',env:{...process.env,KOI_VOICE_DEVELOPMENT:'1',HF_HUB_OFFLINE:'1'}});
child.on('exit',code=>{process.exitCode=code??1;});child.on('error',()=>{console.error('Run setup-voice-tools.py first.');process.exitCode=1;});for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>child.kill(signal));
