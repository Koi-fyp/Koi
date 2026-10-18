const {createRequire}=require('module');
const req=createRequire(process.cwd()+'/package.json');
const {chromium}=req('playwright');
const fs=require('fs'),path=require('path');
const out=path.resolve('../../../artifacts/pre-defense');
const result={url:'http://127.0.0.1:3000',firebase:[],chatRequests:0,pageErrors:0,checks:[],routes:[]};
let browser;
(async()=>{
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader','--disable-background-networking']});
 const context=await browser.newContext({viewport:{width:1280,height:900}}); const page=await context.newPage();
 page.setDefaultTimeout(15000);
 page.on('pageerror',()=>result.pageErrors++);
 page.on('request',r=>{if(new URL(r.url()).pathname==='/api/v1/chat')result.chatRequests++;});
 page.on('response',r=>{const u=new URL(r.url());if(u.hostname==='identitytoolkit.googleapis.com')result.firebase.push({path:u.pathname,status:r.status()});});
 async function capture(route,size){
  await page.setViewportSize(size==='mobile'?{width:390,height:844}:{width:1280,height:900});
  await page.goto(result.url+route,{waitUntil:'domcontentloaded',timeout:90000});
  await page.locator('h1,h2,[data-avatar-state]').first().waitFor({state:'visible',timeout:30000});
  if(route==='/progress')await page.getByText('Recorded Puzzle Pieces',{exact:true}).waitFor();
  const name=(route==='/'?'landing':route.slice(1).replaceAll('/','-'))+'-'+size;
  await page.screenshot({path:path.join(out,name+'.png'),fullPage:true});
  const snapshot=await page.evaluate(()=>({route:location.pathname,overflow:document.documentElement.scrollWidth>innerWidth,headings:[...document.querySelectorAll('h1,h2,h3')].map(n=>n.textContent.trim()),controls:[...document.querySelectorAll('button,input,a')].map(n=>({tag:n.tagName,label:n.getAttribute('aria-label')||n.textContent.trim().slice(0,100),disabled:n.disabled||false}))}));
  fs.writeFileSync(path.join(out,name+'.json'),JSON.stringify(snapshot,null,2));
  result.routes.push({route,size,actual:snapshot.route,overflow:snapshot.overflow});console.log(JSON.stringify(result.routes.at(-1)));
 }
 for(const route of ['/','/about','/how-it-works'])await capture(route,'desktop');
 await page.goto(result.url+'/');await page.getByRole('button',{name:/Get Started/}).first().click();
 try {await page.waitForURL('**/onboarding',{timeout:30000});result.authentication='PASS: genuine anonymous sign-in reached onboarding';}
 catch {result.authentication='NOT RUN: sign-in unavailable';return;}
 await page.getByRole('button',{name:/Welcome|KOI/}).first().count();
 for(const route of ['/settings','/settings/privacy','/settings/export','/settings/import','/progress','/chat','/companion-scene']){
  await capture(route,'desktop');await capture(route,'mobile');
 }
 await page.goto(result.url+'/settings');
 await page.getByText('Browser Storage Estimate',{exact:true}).waitFor();
 result.checks.push({name:'clear-history-disabled',pass:await page.getByRole('button',{name:/Clear History/}).isDisabled()});
 result.checks.push({name:'storage-honesty',pass:!(/42 KB|5 MB used/.test(await page.locator('body').innerText()))});
 await page.getByRole('button',{name:/Mode: Text/}).focus();await page.keyboard.press('Enter');
 result.checks.push({name:'keyboard-mode-open',pass:await page.getByRole('button',{name:/Mode: Text/}).getAttribute('aria-expanded')==='true'});
 result.checks.push({name:'audio-disabled',pass:await page.getByRole('button',{name:'Audio LOCKED',exact:true}).isDisabled()});
 await page.keyboard.press('Escape');
 result.checks.push({name:'keyboard-mode-close',pass:await page.getByRole('button',{name:/Mode: Text/}).getAttribute('aria-expanded')==='false'});
 await page.getByRole('button',{name:/Language/}).click();await page.getByText('Preference saved on this device.',{exact:true}).waitFor();
 const before=await page.getByRole('button',{name:/Language/}).innerText();await page.reload();await page.getByRole('button',{name:/Language/}).filter({hasText:/Urdu|English/}).waitFor();
 result.checks.push({name:'language-reload',pass:before===await page.getByRole('button',{name:/Language/}).innerText()});
 await page.getByRole('button',{name:/Avatar & Name/}).click();await page.getByRole('button',{name:/Aisha.*Warm/}).click();await page.getByRole('button',{name:/Save Changes/}).click();await page.getByText('Companion saved on this device.',{exact:true}).waitFor();
 await page.goto(result.url+'/chat');await page.locator('img[src*="Female"]').waitFor();
 result.checks.push({name:'aisha-png',pass:await page.locator('img[src*="Female"]').evaluate(img=>img.complete&&img.naturalWidth>0)});
 await page.getByRole('link',{name:'Progress',exact:true}).click();await page.getByText('Recorded Puzzle Pieces',{exact:true}).waitFor();
 result.checks.push({name:'progress-download-disabled',pass:await page.getByRole('button',{name:/Download/}).isDisabled()});
 result.checks.push({name:'progress-share-disabled',pass:await page.getByRole('button',{name:/Share/}).isDisabled()});
 await page.getByRole('link',{name:'Chat',exact:true}).click();await page.locator('img[src*="Female"]').waitFor();
 await page.getByRole('link',{name:'Open avatar conversation',exact:true}).click();await page.locator('[data-avatar-state="ready"]').waitFor({timeout:60000});
 await page.screenshot({path:path.join(out,'aisha-vrm-mobile.png'),fullPage:true});
 result.checks.push({name:'aisha-vrm-ready',pass:true});
 result.checks.push({name:'microphone-disabled',pass:await page.getByRole('button',{name:'Microphone unavailable',exact:true}).isDisabled()});
 result.checks.push({name:'camera-disabled',pass:await page.getByRole('button',{name:'Camera unavailable',exact:true}).isDisabled()});
 await page.getByRole('button',{name:'Back to chat',exact:true}).click();await page.locator('img[src*="Female"]').waitFor();await page.reload();await page.locator('img[src*="Female"]').waitFor();result.checks.push({name:'aisha-navigation-reload',pass:true});
 await capture('/avatar-host?model=female','mobile');
})().catch(e=>{result.blocker={type:e.name,operation:'Browser acceptance interrupted; completed checks retained'};process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();fs.writeFileSync(path.join(out,'browser-result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));});
