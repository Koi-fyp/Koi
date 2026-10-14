const assert = require('node:assert/strict'), fs = require('node:fs/promises'), path = require('node:path'), crypto = require('node:crypto');
const { chromium } = require('playwright'), attachAudit = require('./avatar-browser-audit.cjs');
(async () => {
  const origin = 'http://127.0.0.1:3001', output = path.resolve('dev/avatar-sandbox/.next/verification/increment-6b1'); await fs.mkdir(output, { recursive:true });
  const browser = await chromium.launch({ headless:true, executablePath:process.env.KOI_AVATAR_BROWSER, args:['--use-angle=swiftshader','--enable-unsafe-swiftshader'] });
  try {
    const page = await browser.newPage({ viewport:{ width:1280,height:900 } }), audit = await attachAudit(page,origin);
    await page.addInitScript(() => { const Original=window.Audio; window.__testAudio=[]; window.Audio=class extends Original { constructor(...args){ super(...args); window.__testAudio.push(this); } }; });
    await page.goto(origin+'/speech-lab');
    const ready=() => page.waitForFunction(() => window.AvatarController?.ready && window.__koiSpeechLab,null,{timeout:120000}); await ready();
    const zero=() => page.waitForFunction(() => Object.values(window.AvatarController.getSnapshot().animation.mouthWeights).every(value => value===0));
    const play=async () => { await page.getByRole('button',{name:'Play sample',exact:true}).click(); await page.waitForFunction(() => window.__koiSpeechLab.getSnapshot().state==='playing'); };
    async function select(id) { await page.getByLabel('Speech sample',{exact:true}).selectOption(id); await page.getByRole('button',{name:'Play sample',exact:true}).waitFor(); await page.waitForFunction(() => window.__koiSpeechLab.getSnapshot().state==='idle'); }
    const samples=[], results=[];
    async function collect(ms) {
      return page.evaluate(async ms => {
        const values=[], end=performance.now()+ms;
        while(performance.now()<end){
          await new Promise(resolve=>requestAnimationFrame(resolve));
          const frame=window.__koiSpeechLab.getFrame(), animation=window.AvatarController.getSnapshot().animation, applied=animation.speech;
          const cue=frame.cues.find(cue=>applied.time>=cue.start&&applied.time<cue.end), map={A:null,B:'ih',C:'ee',D:'aa',E:'oh',F:'ou',G:'ih',H:'ee',X:null};
          const preset=applied.active&&cue?map[cue.value]:null;
          let expected=0;
          if(preset){const ramp=Math.min(.04,(cue.end-cue.start)/2), t=Math.max(0,Math.min(1,(applied.time-cue.start)/ramp,(cue.end-applied.time)/ramp));expected=.7*t*t*(3-2*t);}
          values.push({audioTime:frame.time,appliedTime:applied.time,timeDifference:frame.time-applied.time,preset,expected,weights:animation.mouthWeights,blink:animation.blinkWeight,emotion:animation.emotion});
        } return values;
      },ms);
    }
    const ids=['piper-urdu','piper-english','piper-mixed'];
    for(const model of ['male','female']){
      if(model==='female'){
        await play(); await page.getByRole('button',{name:'Preview settings'}).click(); await page.getByLabel('Preview model',{exact:true}).selectOption('female');
        await page.waitForFunction(()=>window.AvatarController?.ready&&window.AvatarController.getSnapshot().modelUrl.includes('female'),null,{timeout:120000});
        assert.equal(await page.evaluate(()=>window.__koiSpeechLab.getSnapshot().state),'stopped'); await zero();
        await page.getByRole('button',{name:'Preview settings'}).click();
      }
      for(const id of ids){
        await select(id);
        const manifest=await (await page.request.get(origin+'/speech-fixture/'+id+'.json')).json();
        assert.equal(manifest.kind,'rhubarb'); assert.equal(manifest.voice,'ur_PK-fasih-medium');
        const response=await page.request.get(origin+'/speech-fixture/'+id+'.wav?sha256='+manifest.sha256);assert.equal(response.status(),200);
        assert.equal(crypto.createHash('sha256').update(await response.body()).digest('hex'),manifest.sha256);
        const wrong=await page.request.get(origin+'/speech-fixture/'+id+'.wav?sha256='+'0'.repeat(64));assert.equal(wrong.status(),409);
        assert.match(await page.locator('main').innerText(),/actual Piper audio and Rhubarb cues/);
        await play(); const recorded=await collect(Math.ceil(manifest.durationSeconds*1000)+400); samples.push(...recorded);
        await page.waitForFunction(()=>window.__koiSpeechLab.getSnapshot().state==='ended'); await zero();
        await page.getByLabel('Speech sample',{exact:true}).selectOption(id);
        assert(await page.getByRole('button',{name:'Play sample',exact:true}).isEnabled(),'reselecting the active sample must preserve replay');
        assert(recorded.some(sample=>Object.values(sample.weights).some(value=>value>.1)),id+' must actually animate a mouth preset');
        results.push({id,model,audioHashVerified:true,cueCount:manifest.mouthCues.length,durationSeconds:manifest.durationSeconds,synthesisSeconds:manifest.synthesisSeconds,cueExtractionSeconds:manifest.cueExtractionSeconds,pronunciation:'not human evaluated',alignmentQuality:'no human/ground-truth evaluation'});
      }
    }
    await select('piper-english'); await play(); await page.waitForTimeout(200);
    await page.getByRole('button',{name:'Pause',exact:true}).click(); await zero();
    const at=await page.evaluate(()=>window.__koiSpeechLab.getFrame().time); await page.waitForTimeout(200);assert.equal(await page.evaluate(()=>window.__koiSpeechLab.getFrame().time),at);
    await page.getByRole('button',{name:'Resume',exact:true}).click(); await page.waitForFunction(()=>window.__koiSpeechLab.getSnapshot().state==='playing');
    await page.evaluate(()=>window.__koiSpeechLab.seek(.2)); samples.push(...await collect(300));
    await page.getByRole('button',{name:'Stop',exact:true}).click(); await zero();
    for(let index=0;index<3;index++){await play();await page.getByRole('button',{name:'Stop',exact:true}).click();}await zero();
    await page.getByRole('button',{name:'Preview settings'}).click();
    for(const emotion of ['neutral','joy','angry','sorrow','fun']){
      await page.getByLabel('Speech emotion').selectOption(emotion);await play(); samples.push(...await collect(450));
      assert.equal(await page.evaluate(()=>window.AvatarController.getSnapshot().animation.emotion),emotion);
      await page.getByRole('button',{name:'Stop',exact:true}).click();await zero();
    }
    await page.getByRole('button',{name:'Preview settings'}).click();await select('piper-urdu');await play();
    await page.screenshot({path:path.join(output,'desktop-real-speech.png')});
    await page.setViewportSize({width:390,height:844});await page.waitForTimeout(200);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    await page.screenshot({path:path.join(output,'mobile-real-speech.png')});
    await select('speech-sample');assert.match(await page.locator('main').innerText(),/manually authored approximate cues/);await play();
    // A sample switch interrupts the baseline too, and returns to real automatic data.
    await select('piper-urdu');await zero();
    await page.getByRole('button',{name:'End conversation'}).click();await page.getByRole('heading',{name:'KOI development sandbox'}).waitFor();await page.waitForTimeout(300);
    const cleanup=await page.evaluate(()=>({frames:window.__avatarAudit.pending.size,observers:window.__avatarAudit.observers.size,contexts:window.__avatarAudit.contexts.filter(gl=>!gl.isContextLost()).length,mediaCalls:window.__avatarAudit.mediaCalls,activeAudio:window.__testAudio.filter(audio=>!audio.paused||audio.getAttribute('src')).length,diagnosticRemoved:!window.__koiSpeechLab}));
    assert.deepEqual(cleanup,{frames:0,observers:0,contexts:0,mediaCalls:0,activeAudio:0,diagnosticRemoved:true});
    for(const sample of samples)for(const [name,value] of Object.entries(sample.weights))assert(Math.abs(value-(name===sample.preset?sample.expected:0))<1e-7,'mouth must match real cue at consumed audio time');
    assert(samples.some(sample=>sample.blink>.5));
    const differences=samples.map(sample=>Math.abs(sample.timeDifference)).filter(Number.isFinite).sort((a,b)=>a-b);
    const sync={samples:differences.length,maxMediaFrameDifferenceSeconds:differences.at(-1),p95MediaFrameDifferenceSeconds:differences[Math.floor(differences.length*.95)],method:'Current audio.currentTime minus media time consumed by last avatar frame, not acoustic/phoneme accuracy'};
    assert(sync.maxMediaFrameDifferenceSeconds<.5);assert.deepEqual(audit.errors,[]);assert.deepEqual(audit.consoleErrors,[]);assert.deepEqual(audit.external,[]);
    const result={passed:true,scope:'Actual local Piper synthesis + actual Rhubarb cues + browser playback; physical output and linguistic quality not verified',results,sync,cleanup,...audit};
    await fs.writeFile(path.join(output,'samples.json'),JSON.stringify(samples,null,2));await fs.writeFile(path.join(output,'results.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
