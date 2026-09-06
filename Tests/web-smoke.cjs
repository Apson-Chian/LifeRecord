const { chromium } = require('playwright');
const fs = require('fs');
const assert = require('assert/strict');
(async () => {
 const browser = await chromium.launch({headless:true,channel:"chrome"});
 const page = await browser.newPage({viewport:{width:1440,height:1100}});
 const errors=[]; page.on('pageerror', e => errors.push(e.message));
 const timestamp = Date.now()/1000;
 let snapshot={meals:[{id:'d0a4f4ee-2222-4444-8888-555555555555',date:timestamp,kind:'午餐',name:'鸡胸肉拌饭',calories:650,protein:42,carbs:78,fat:18,fiber:5,note:'米饭 200g',source:'AI 估算',createdAt:timestamp-3600,updatedAt:timestamp,photoIDs:[]}],bodyMetrics:[],waterEntries:[],deletions:[],settings:null};
 await page.route('http://liferecord.test/**', async route => {
  const url=new URL(route.request().url());
  if(url.pathname.startsWith('/liferecord-api')) {
   if(url.pathname.endsWith('/sync')) snapshot=JSON.parse(route.request().postData());
   return route.fulfill({json:snapshot});
  }
  const name=url.pathname==='/'?'index.html':url.pathname.slice(1);
  return route.fulfill({body:fs.readFileSync(require('path').join(__dirname, '../Web', name)),contentType:name.endsWith('.js')?'text/javascript':name.endsWith('.css')?'text/css':'text/html'});
 });
 await page.goto('http://liferecord.test/');
 await page.getByRole('button',{name:'编辑',exact:true}).click();
 await page.locator('[name=calories]').fill('325');
 await page.locator('[name=protein]').fill('0');
 await page.locator('#mealForm [name=note]').fill('只吃了一半');
 await page.getByRole('button',{name:'保存记录',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#mealDialog').open);
 assert.equal(snapshot.meals.length,1); assert.equal(snapshot.meals[0].calories,325); assert.equal(snapshot.meals[0].protein,0);
 assert.equal(snapshot.meals[0].source,'AI 估算'); assert.equal(snapshot.meals[0].createdAt,timestamp-3600); assert.equal(snapshot.meals[0].fiber,5); assert.equal(snapshot.meals[0].date,timestamp);
 await page.locator('#mealSearch').fill('不存在'); assert.equal(await page.locator('#mealPreview tr').count(),1); assert.match(await page.locator('#mealPreview').innerText(),/没有匹配/);
 await page.locator('#mealSearch').fill('');
 await page.screenshot({path:'/tmp/liferecord-desktop.png',fullPage:true});
 for(const width of [390,768,1024,1440]) { await page.setViewportSize({width,height:900}); if (!(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth))) console.log(await page.evaluate(()=>[...document.querySelectorAll("body *")].filter(e=>e.getBoundingClientRect().right>innerWidth).map(e=>[e.tagName,e.className,e.getBoundingClientRect().right]).slice(0,25))); assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),`overflow at ${width}`); }
 await page.setViewportSize({width:390,height:844}); await page.screenshot({path:'/tmp/liferecord-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]); console.log('PASS: edit-in-place, zero values, metadata preservation, search, 4 responsive widths, no browser errors');
 await browser.close();
})();
