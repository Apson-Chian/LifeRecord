// Browser login forms with in-memory fake APIs; never connects to a real account.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
(async () => {
  const browser = await chromium.launch({headless:true,channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:390,height:844}});
    const errors = [];
    const calls = [];
    let authorized = false;
    let bound = false;
    page.on('pageerror', error => errors.push(error.message));
    await page.route('https://liferecord.test/**', async route => {
      const url = new URL(route.request().url());
      if(url.pathname.startsWith('/liferecord-api/')) {
        const endpoint = url.pathname.replace('/liferecord-api','');
        const body = route.request().postDataJSON();
        calls.push({endpoint,body});
        if(endpoint === '/auth') {authorized = body.token === 'fixture-invitation';return route.fulfill({status:authorized?204:401,json:authorized?undefined:{error:'同步密钥不正确'}});}
        if(endpoint === '/logout') {authorized=false;return route.fulfill({status:204});}
        if(endpoint === '/account/register') {authorized=true;bound=true;return route.fulfill({json:{userId:'registered-user',username:body.username,token:'fixture-registered-session'}});}
        if(endpoint === '/account/login') {
          if(body.password !== 'fixture-password-42') return route.fulfill({status:401,json:{error:'账号或密码不正确'}});
          authorized=true;return route.fulfill({json:{userId:'fixture-a',username:body.username,token:'fixture-session'}});
        }
        if(!authorized) return route.fulfill({status:401,json:{error:'需要登录'}});
        if(endpoint === '/account/me') return route.fulfill({json:{userId:'fixture-a',username:bound?'fixture.user':''}});
        if(endpoint === '/account/credentials') {bound=true;return route.fulfill({json:{userId:'fixture-a',username:body.username,token:'fixture-rotated-session'}});}
        return route.fulfill({json:{meals:[],bodyMetrics:[],workoutEntries:[],deletions:[],settings:null}});
      }
      const name = url.pathname === '/' ? 'index.html' : path.basename(url.pathname);
      const file = path.join(__dirname,'../Web',name);
      if(!fs.existsSync(file)) return route.fulfill({status:404,body:''});
      return route.fulfill({body:fs.readFileSync(file),contentType:name.endsWith('.js')?'application/javascript':name.endsWith('.css')?'text/css':'text/html'});
    });
    await page.goto('https://liferecord.test/');
    await page.locator('#authDialog[open]').waitFor();
    assert.equal(await page.locator('#authTokenField').isVisible(),false);
    await page.locator('#authForm [name=username]').fill('fixture.user');
    await page.locator('#authForm [name=password]').fill('wrong-password-42');
    await page.locator('#authSubmit').click();
    await page.getByText('账号或密码不正确',{exact:true}).waitFor();
    await page.locator('#authForm [name=password]').fill('fixture-password-42');
    await page.locator('#authSubmit').click();
    await page.waitForFunction(() => !document.querySelector('#authDialog').open);
    assert.equal(await page.locator('#authForm [name=password]').inputValue(),'');
    await page.locator('.topbar [data-open-settings]').click();
    await page.locator('#accountPasswordButton').click();
    await page.locator('#accountPasswordDialog[open]').waitFor();
    assert.equal(await page.locator('#accountCurrentField').isVisible(),false);
    await page.locator('#accountUsername').fill('fixture.user');
    await page.locator('#accountPasswordForm [name=password]').fill('fixture-password-42');
    await page.locator('#accountPasswordForm [name=confirmation]').fill('different-password-42');
    await page.locator('#accountPasswordForm [type=submit]').click();
    await page.locator('#accountPasswordError').getByText('两次输入的密码不一致',{exact:true}).waitFor();
    assert.equal(calls.filter(call=>call.endpoint==='/account/credentials').length,0);
    await page.locator('#accountPasswordForm [name=confirmation]').fill('fixture-password-42');
    await page.locator('#accountPasswordForm [type=submit]').click();
    await page.waitForFunction(() => !document.querySelector('#accountPasswordDialog').open);
    await page.locator('#changeKeyButton').click();
    await page.locator('#authDialog[open]').waitFor();
    await page.locator('#authMode').selectOption('register');
    assert.equal(await page.locator('#authTokenField').isVisible(),false);
    await page.locator('#authForm [name=username]').fill('fixture.user');
    await page.locator('#authForm [name=password]').fill('fixture-password-42');
    await page.locator('#authForm [name=confirmation]').fill('different-password-42');
    await page.locator('#authSubmit').click();
    await page.locator('#authError').getByText('两次输入的密码不一致',{exact:true}).waitFor();
    assert.equal(calls.filter(call=>call.endpoint==='/account/register').length,0);
    await page.locator('#authForm [name=confirmation]').fill('fixture-password-42');
    await page.locator('#authSubmit').click();
    await page.waitForFunction(() => !document.querySelector('#authDialog').open);
    assert.equal(calls.filter(call=>call.endpoint==='/account/register').length,1);
    assert.equal(calls.filter(call=>call.endpoint==='/auth').length,0);
    const storage = await page.evaluate(() => JSON.stringify({...localStorage,...sessionStorage}));
    assert(!storage.includes('fixture-password-42'));
    assert(!storage.includes('fixture-session'));
    assert.deepEqual(errors,[]);
    console.log('PASS: mobile password login, failure/retry, self-service registration, confirmation, password clearing and storage privacy');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
