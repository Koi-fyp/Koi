const { createRequire } = require('node:module');
const requireApp = createRequire(process.cwd() + '/package.json');
const { chromium } = requireApp('playwright');
const readline = require('node:readline');
const { createHash } = require('node:crypto');
const base = 'http://127.0.0.1:3000';
let browser, context, page;
const network = { firebase: [], modal: [], failures: [], pageErrors: 0, documents: [] };
const sha = value => createHash('sha256').update(value).digest('hex').slice(0, 16);
async function inspect() {
  return page.evaluate(async () => {
    const hash = async value => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))).map(x => x.toString(16).padStart(2,'0')).join('').slice(0,16);
    let auth, manager;
    const visited = new Set();
    for (const el of document.querySelectorAll('textarea,button,main,a')) {
      let fiber = el[Object.keys(el).find(key => key.startsWith('__reactFiber$'))];
      while (fiber && !visited.has(fiber)) {
        visited.add(fiber);
        const value = fiber.memoizedProps?.value;
        if (value && typeof value.signOut === 'function' && 'user' in value) auth = value;
        if (value && typeof value.initialize === 'function' && 'session' in value) manager = value;
        fiber = fiber.return;
      }
    }
    const snapshot = manager?.session?.getSnapshot();
    const messages = snapshot?.messages ?? [];
    const completed = messages.filter(m => m.status === 'completed').slice(-5).map(m => ({ role: m.sender === 'user' ? 'user' : 'assistant', content: m.content }));
    const textarea = document.querySelector('textarea');
    const safe = {
      route: location.pathname,
      auth: { found: !!auth, signedIn: !!auth?.user, anonymous: auth?.user?.isAnonymous === true, ownerFingerprint: auth?.user ? await hash(auth.user.uid) : null },
      session: snapshot ? { conversationFingerprint: await hash(manager.session.conversationId), count: messages.length,
        ids: await Promise.all(messages.map(m => hash(m.id))), roles: messages.map(m => m.sender), statuses: messages.map(m => m.status),
        pending: snapshot.pending, errorPresent: !!snapshot.error, completedHistoryFingerprint: await hash(JSON.stringify(completed)),
        eventNames: snapshot.serverEvents.map(e => e.event.event), exerciseStatePresent: !!snapshot.exerciseState } : null,
      inputPresent: !!textarea, inputDisabled: textarea?.disabled ?? null,
      recoveryError: /Conversation history could not be unlocked|Conversation storage changed or is unavailable/.test(document.body.innerText),
      firebaseConfigError: /Firebase sign-in is unavailable|environment is not fully configured/.test(document.body.innerText),
      signInFailed: /Sign-in could not connect|Anonymous sign-in is disabled/.test(document.body.innerText),
      buttons: Array.from(document.querySelectorAll('button')).map(b => ({ name: b.getAttribute('aria-label') || b.textContent?.trim().slice(0,65), disabled:b.disabled })),
    };
    if (auth?.user && manager?.session && (await indexedDB.databases()).some(db => db.name === 'KoiDB')) {
      safe.storage = await new Promise(resolve => {
        const request = indexedDB.open('KoiDB');
        request.onerror = () => resolve({ accessible:false });
        request.onsuccess = () => {
          const db = request.result;
          const tx = db.transaction(['conversations','messages'],'readonly');
          const header = tx.objectStore('conversations').get(auth.user.uid);
          const rows = tx.objectStore('messages').index('conversationId').getAll(manager.session.conversationId);
          tx.oncomplete = () => { resolve({ accessible:true, headerOwned:header.result?.uid === auth.user.uid,
            snapshotEncrypted:typeof header.result?.encryptedState === 'string' && header.result.encryptedState.startsWith('v1:PBKDF2:'), revision:header.result?.revision ?? null,
            rows: rows.result.length, allRowsOwned:rows.result.every(r => r.ownerUid === auth.user.uid), allContentsEncrypted:rows.result.every(r => typeof r.content === 'string' && r.content.startsWith('v1:PBKDF2:')) }); db.close(); };
          tx.onerror = () => { resolve({ accessible:false }); db.close(); };
        };
      });
    }
    const stat = label => { const el=Array.from(document.querySelectorAll('p')).find(p=>p.textContent===label); const value=el?.parentElement?.querySelector('p')?.textContent; return /^\d+$/.test(value ?? '') ? Number(value) : null; };
    const pieceLabel=Array.from(document.querySelectorAll('p')).find(p=>p.textContent?.trim()==='Recorded Puzzle Pieces');
    const pieceValue=pieceLabel?.nextElementSibling?.querySelector('p')?.textContent?.trim();
    safe.progressUi={ completedExchanges:stat('Completed Exchanges'),conversations:stat('Conversations With Replies'),milestones:stat('Recorded Milestones'),pieces:/^\d+$/.test(pieceValue ?? '')?Number(pieceValue):null,previewNotice:!!document.querySelector('[role="note"]'),previewHeadings:Array.from(document.querySelectorAll('h2,h3')).filter(h=>h.textContent.includes('Preview')).length };
    return safe;
  });
}
async function setup() {
  browser = await chromium.launch({ executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe', headless:true,
    args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-background-networking'] });
  context = await browser.newContext({ viewport:{width:1100,height:850} });
  await context.addInitScript(() => {
    window.__p0Sse = [];
    const original = window.fetch;
    window.fetch = async function(...args) {
      const input = args[0];
      const url = typeof input === 'string' ? input : input instanceof Request ? input.url : String(input);
      const response = await original.apply(this,args);
      if (new URL(url,location.href).pathname === '/api/v1/chat') {
        const item = { status:response.status, contentType:response.headers.get('content-type'), events:[], ended:false, readFailed:false };
        window.__p0Sse.push(item);
        if (response.body && (item.contentType ?? '').includes('text/event-stream')) {
          void (async () => {
            const reader = response.clone().body.getReader(), decoder = new TextDecoder(); let buffer = '';
            try { while (true) {
              const chunk = await reader.read(); if (chunk.done) break;
              buffer += decoder.decode(chunk.value,{stream:true});
              const lines = buffer.split(/\r?\n/); buffer = lines.pop();
              for (const line of lines) if (line.startsWith('event:')) {
                const name=line.slice(6).trim();
                item.events.push(['latency','delta','state','companion_state','risk','error','done','ui_action','handoff','transcript'].includes(name) ? name : 'unknown');
                if(name==='done') item.doneRoute=location.pathname;
                if(window.__p0ArmNavigation && name!=='done') {
                  window.__p0ArmNavigation=false;
                  const link=document.querySelector('a[href="/progress"]');
                  item.navigation={onEvent:name,doneAlreadyObserved:item.events.includes('done'),streamEnded:item.ended,routeBefore:location.pathname,linkFound:!!link};
                  link?.click();
                }
              }
            } item.ended=true; } catch { item.readFailed=true; }
          })();
        }
      }
      return response;
    };
  });
  await context.addInitScript(() => {
    window.__p1Audit={contexts:[],observers:new Set(),frames:new Set()};
    const get=HTMLCanvasElement.prototype.getContext; HTMLCanvasElement.prototype.getContext=function(...args){const value=get.apply(this,args);if(value&&args[0]==='webgl2'&&!window.__p1Audit.contexts.includes(value))window.__p1Audit.contexts.push(value);return value;};
    const RO=window.ResizeObserver;window.ResizeObserver=class extends RO{observe(...args){window.__p1Audit.observers.add(this);return super.observe(...args);}disconnect(){window.__p1Audit.observers.delete(this);return super.disconnect();}};
    const raf=window.requestAnimationFrame.bind(window),caf=window.cancelAnimationFrame.bind(window);window.requestAnimationFrame=fn=>{const id=raf(t=>{window.__p1Audit.frames.delete(id);fn(t);});window.__p1Audit.frames.add(id);return id;};window.cancelAnimationFrame=id=>{window.__p1Audit.frames.delete(id);caf(id);};
  });
  page = await context.newPage();
  page.on('pageerror', error => {network.pageErrors++; network.errorTypes ??= []; network.errorTypes.push({name:error.name,hydration:/hydration|Hydration|Minified React|server rendered|initial UI/.test(error.message),chunk:/ChunkLoadError|Loading chunk|Cannot find module/.test(error.message),knownMessage:/^(Cannot read|Cannot set|Rendered|Invalid hook)/.test(error.message)?error.message.slice(0,150):'other runtime error'});});
  page.on('request', request => {
    const url = new URL(request.url());
    if (url.pathname === '/api/v1/chat') {
      let history = [];
      try { history = request.postDataJSON()?.session_history ?? []; } catch {}
      network.modal.push({ origin:url.origin, path:url.pathname, method:request.method(), status:null, contentType:null,
        historyCount:history.length, historyRoles:history.map(h=>h.role), historyFingerprint:sha(JSON.stringify(history)) });
    }
  });
  page.on('response', response => {
    const url = new URL(response.url());
    if(url.pathname.endsWith('.vrm')) { network.models ??= []; network.models.push({path:url.pathname,status:response.status()}); }
    if (url.hostname === 'identitytoolkit.googleapis.com') network.firebase.push({path:url.pathname,status:response.status()});
    if (url.pathname === '/api/v1/chat') {
      const item = network.modal.findLast(r=>r.status===null && r.method===response.request().method());
      if(item) { item.status=response.status(); item.contentType=response.headers()['content-type'] ?? null; }
    }
    if(response.request().isNavigationRequest() && url.origin===base) network.documents.push({path:url.pathname,status:response.status()});
  });
  page.on('requestfailed', request => {
    const url = new URL(request.url());
    if(url.pathname==='/api/v1/chat' || url.hostname==='identitytoolkit.googleapis.com') network.failures.push({origin:url.origin,path:url.pathname,code:(request.failure()?.errorText ?? '').match(/net::[A-Z_]+/)?.[0] ?? 'request_failed'});
  });
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:120000});
  console.log(JSON.stringify({ready:true,url:base,isolatedContext:true}));
}
async function command(data) {
  switch(data.action) {
    case 'audit': return page.evaluate(()=>({liveContexts:window.__p1Audit.contexts.filter(c=>!c.isContextLost()).length,observers:window.__p1Audit.observers.size,frames:window.__p1Audit.frames.size}));
    case 'avatar': return page.evaluate(() => {
      let bridge; for(const el of document.querySelectorAll('[data-avatar-state]')) { let f=el[Object.keys(el).find(k=>k.startsWith('__reactFiber$'))]; while(f){ let h=f.memoizedState; while(h && typeof h==='object'){ if(h.memoizedState?.current?.getSnapshot && h.memoizedState.current?.setEmotion) bridge=h.memoizedState.current; h=h.next; } f=f.return; } }
      const canvas=document.querySelector('canvas'); const rect=canvas?.getBoundingClientRect();
      return {route:location.pathname,selectedCards:Array.from(document.querySelectorAll('[aria-pressed=true]')).map(b=>b.textContent.trim().slice(0,60)),state:document.querySelector('[data-avatar-state]')?.getAttribute('data-avatar-state'),snapshot:bridge?.getSnapshot(),canvasCount:document.querySelectorAll('canvas').length,rect:rect?{width:rect.width,height:rect.height}:null,images:Array.from(document.querySelectorAll('img')).map(i=>({alt:i.alt,src:new URL(i.currentSrc||i.src,location.href).pathname,loaded:i.complete&&i.naturalWidth>0})),overflow:document.documentElement.scrollWidth>innerWidth,textFallback:!!document.querySelector('[aria-label="Conversation transcript"]')};
    });
    case 'shot': await page.screenshot({path:require('node:path').join(require('node:os').tmpdir(),'koi-p1-'+data.name+'.png')}); return {saved:data.name};
    case 'viewport': await page.setViewportSize({width:data.width,height:data.height}); return {resized:true};
    case 'fixture': return page.evaluate(async data=>{
      let manager; for(const el of document.querySelectorAll('textarea,button,main,a')){ let f=el[Object.keys(el).find(k=>k.startsWith('__reactFiber$'))]; while(f){ const v=f.memoizedProps?.value;if(v&&typeof v.initialize==='function'&&'session' in v) manager=v;f=f.return; } }
      if(!manager?.session) return {unavailable:true}; const s=manager.session, original=s.adapter;
      s.adapter={send:async(request,options)=>{options.onEvent?.({event:'companion_state',data:{emotion:data.emotion??'neutral',intensity:data.intensity??0}});return {reply:'Simulated avatar integration check.',companion_state:{emotion:data.emotion??'neutral',intensity:data.intensity??0},latency_ms:1};}};
      try{await s.send('Synthetic local avatar fixture.');return {simulated:true};}finally{s.adapter=original;}
    },data);
    case 'failModel': await page.route('**/models/*.vrm',r=>r.fulfill({status:404,body:'synthetic missing model'}));return {simulated:true};
    case 'restoreModel': await page.unroute('**/models/*.vrm');return {restored:true};
    case 'loseContext': await page.locator('canvas').evaluate(c=>c.getContext('webgl2')?.getExtension('WEBGL_lose_context')?.loseContext());return {simulated:true};
    case 'inspect': return {view:await inspect(),network,sse:await page.evaluate(()=>window.__p0Sse ?? [])};
    case 'click': await page.getByRole(data.role ?? 'button',{name:data.name,exact:data.exact ?? false}).first().click({timeout:15000}); return {clicked:true,route:new URL(page.url()).pathname};
    case 'check': { const boxes=page.getByRole('checkbox'); for(let i=0;i<await boxes.count();i++) if(await boxes.nth(i).getAttribute('aria-checked')!=='true') await boxes.nth(i).click(); return {checked:true}; }
    case 'send': { const phrases=['Hello. This is a non-sensitive continuity test. Please reply briefly.','For this test, remember the word lantern. Please acknowledge briefly.','What word did I ask you to remember? Please reply briefly.','Please give one short suggestion for a pleasant afternoon.']; await page.locator('textarea').fill(phrases[data.index ?? 0]); await page.getByRole('button',{name:'Send message',exact:true}).click({timeout:15000}); return {submitted:true,index:data.index ?? 0}; }
    case 'streamNavigate': {
      await page.evaluate(()=>{window.__p0ArmNavigation=true;});
      await page.locator('textarea').fill('This is a non-sensitive software continuity check. Please list twelve brief, neutral ideas for arranging a bookshelf.');
      await page.getByRole('button',{name:'Send message',exact:true}).click({timeout:15000});
      return {armedFirstFrameNavigation:true,submitted:true};
    }
    case 'reload': await page.reload({waitUntil:'domcontentloaded',timeout:120000}); return {reloaded:true};
    case 'goto': await page.goto(base+data.path,{waitUntil:'domcontentloaded',timeout:120000}); return {route:new URL(page.url()).pathname};
    case 'logout': return page.evaluate(async()=>{
      const visited=new Set();
      for(const el of document.querySelectorAll('textarea,button,main,a')) {
        let fiber=el[Object.keys(el).find(k=>k.startsWith('__reactFiber$'))];
        while(fiber&&!visited.has(fiber)){visited.add(fiber); const val=fiber.memoizedProps?.value;
          if(val&&typeof val.signOut==='function'&&'user' in val){await val.signOut();return {applicationSignOutInvoked:true};} fiber=fiber.return; }
      } return {applicationSignOutInvoked:false};
    });
    case 'close': await browser.close(); return {closed:true};
    default: return {error:'unknown_action'};
  }
}

const fs=require('fs'),path=require('path');
const out=path.resolve('../../../artifacts/increment04-breathing-fixture');
const report={checks:[],routes:[],failures:[],live:null};
async function check(name,fn){try{const value=await fn();report.checks.push({name,result:value===false?'FAIL':'PASS',evidence:value});console.log(JSON.stringify(report.checks.at(-1)));}catch(e){report.failures.push({name,type:e.name});console.log(JSON.stringify({check:name,result:'NOT RUN',type:e.name}));}}
async function shot(name){await page.screenshot({path:path.join(out,name+'.png'),fullPage:true});}
async function capture(route){await command({action:'goto',path:route});await page.locator('h1,h2,[data-avatar-state]').first().waitFor({timeout:30000});if(route==='/progress')await page.getByText('Recorded Puzzle Pieces',{exact:true}).waitFor();const snapshot=await page.evaluate(()=>({route:location.pathname,headings:[...document.querySelectorAll('h1,h2,h3')].map(n=>n.textContent.trim()),controls:[...document.querySelectorAll('button,input,a,[role=button]')].map(n=>({tag:n.tagName,name:n.getAttribute('aria-label')||n.textContent.trim().slice(0,110),disabled:n.disabled||false,href:n.getAttribute('href')})),overflow:document.documentElement.scrollWidth>innerWidth}));report.routes.push(snapshot);fs.writeFileSync(path.join(out,(route==='/'?'landing':route.slice(1).replace(/[^a-z0-9-]/gi,'-'))+'.json'),JSON.stringify(snapshot,null,2));console.log(JSON.stringify({visited:snapshot.route,overflow:snapshot.overflow}));}



async function metadata(target=page){return target.evaluate(async()=>{
 let req;window.webpackChunk_N_E.push([[Date.now()],{},r=>{req=r;}]);
 const services=req(Object.keys(req.m).find(k=>k.endsWith('/src/lib/firebase.ts'))), db=req(Object.keys(req.m).find(k=>k.endsWith('/src/lib/db.ts'))).db;
 const uid=services.auth.currentUser.uid, events=await db.activityEvents.where('owner_uid').equals(uid).toArray(), rewards=await db.rewardReceipts.where('owner_uid').equals(uid).toArray(), milestones=await db.milestoneReceipts.where('owner_uid').equals(uid).toArray();
 return {events:events.length,rewards:rewards.length,milestones:milestones.map(m=>m.milestone),sources:events.map(e=>e.source_type),slots:rewards.map(r=>r.slot_index).sort((a,b)=>a-b),ciphertextsValid:events.filter(e=>e.source_type==='check_in').every(e=>e.payload?.startsWith('v1:PBKDF2:')),noPlaintextRatings:events.every(e=>!Object.keys(e).some(k=>['mood','connection','energy'].includes(k))&&!Object.keys(e.provenance).some(k=>['mood','connection','energy'].includes(k))),databaseVersion:db.verno};
});}
async function formReady(){await page.getByRole('button',{name:'Save check-in',exact:true}).waitFor();await page.waitForFunction(()=>[...document.querySelectorAll('button')].some(b=>b.textContent==='Save check-in'&&!b.disabled&&!b.closest('fieldset')?.disabled),{},{timeout:30000});}
async function fill(mood='2',connection='3',energy='4'){await page.getByLabel('Mood',{exact:true}).selectOption(mood);await page.getByLabel('Connection',{exact:true}).selectOption(connection);await page.getByLabel('Energy',{exact:true}).selectOption(energy);await page.getByRole('checkbox').check();}
async function checkCounts(events,rewards){await page.waitForFunction(async expected=>{let req;window.webpackChunk_N_E.push([[Date.now()],{},r=>{req=r;}]);const db=req(Object.keys(req.m).find(k=>k.endsWith('/src/lib/db.ts'))).db;return await db.activityEvents.count()===expected.events&&await db.rewardReceipts.count()===expected.rewards;},{events,rewards},{timeout:30000});}

async function fixtureStart(){return page.evaluate(async()=>{
 let manager;for(const el of document.querySelectorAll('textarea,button,main,a')){let f=el[Object.keys(el).find(k=>k.startsWith('__reactFiber$'))];while(f){const v=f.memoizedProps?.value;if(v&&typeof v.initialize==='function'&&'session'in v)manager=v;f=f.return;}}
 const session=manager.session,original=session.adapter;
 session.adapter={send:async(request,options)=>{const state={emotion:'neutral',intensity:0};options.onEvent({event:'ui_action',data:{name:'start_breathing',args:{inhale_s:4,exhale_s:6,cycles:6,cue_audio:['Breathe in','Breathe out']}}});options.onEvent({event:'done',data:{full_text:'LOCAL FIXTURE: guided breathing integration test.',companion_state:state,ui_actions:[],handoff:null,total_generation_s:0}});return {reply:'LOCAL FIXTURE: guided breathing integration test.',companion_state:state,latency_ms:1};}};
 try{await session.send('Synthetic local exercise fixture, not a Modal response.');return {fixture:true};}finally{session.adapter=original;}
});}
(async()=>{await setup();await page.getByRole('button',{name:/Get Started/}).first().click();await page.waitForURL('**/onboarding',{timeout:30000});
await page.getByRole('button',{name:/I Understand/}).click();await page.getByRole('button',{name:/Aisha.*Female/}).click();await page.getByRole('button',{name:/Continue with Aisha/}).click();await page.getByRole('checkbox',{name:/I understand KOI is an AI/}).check();await page.getByRole('checkbox',{name:/I understand saved history is encrypted/}).check();await page.getByRole('button',{name:/I Agree/}).click();await page.getByRole('button',{name:/Continue/}).click();await page.getByRole('button',{name:/Let's Go/}).click();await page.waitForURL('**/chat',{timeout:45000});await page.locator('textarea').waitFor();await page.goto(base+'/companion-scene');await page.getByRole('button',{name:'Change companion'}).waitFor();
report.kind='LOCAL UI_ACTION FIXTURE; real monotonic browser timing; not a deployed Modal exercise acceptance';await fixtureStart();await page.getByRole('region',{name:'Paced breathing activity'}).waitFor();console.log(JSON.stringify({phase:'LOCAL FIXTURE exercise started, waiting 60 real seconds'}));await page.getByText('Activity complete',{exact:true}).waitFor({timeout:80000});await page.getByText('Client-measured breathing activity saved. One puzzle piece earned.',{exact:true}).waitFor({timeout:20000});
report.receipt=await metadata();await check('FIXTURE ONLY: real 60-second callback creates one client-measured activity and reward',()=>report.receipt.events===1&&report.receipt.rewards===1&&report.receipt.sources[0]==='breathing');
await page.goto(base+'/progress');await formReady();await page.getByRole('button',{name:'Slot 1: recorded unlock',exact:true}).waitFor();await page.reload();await formReady();report.refresh=await metadata();await check('FIXTURE ONLY: client-measured breathing receipt and piece survive refresh',()=>report.refresh.events===1&&report.refresh.rewards===1);await shot('fixture-breathing-piece');
await page.goto(base+'/companion-scene');await page.getByRole('button',{name:'Change companion'}).waitFor();await fixtureStart();await page.getByRole('region',{name:'Paced breathing activity'}).waitFor();await page.getByRole('button',{name:'Stop',exact:true}).click();await page.getByText(/Breathing was not eligible for a reward/).waitFor();await check('FIXTURE ONLY: user-stop interruption creates no new event or piece',async()=>{const p=await metadata();return p.events===1&&p.rewards===1;});
await check('Fixture did not send a Modal request',()=>network.modal.length===0);
})().catch(async e=>{report.failures.push({type:e.name,message:e.message.split('\n')[0]});await shot('failure-state').catch(()=>{});}).finally(async()=>{report.network=network;if(browser)await browser.close();fs.writeFileSync(path.join(out,'browser-result.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));});
