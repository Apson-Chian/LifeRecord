/* Non-secret API preferences persist locally; all keys stay in page memory. */
const API_PREFS_KEY = 'liferecord.api-preferences.v2';
const apiDefaults = {model:'', endpoint:'', authMode:'bearer', authHeader:'', maxTokens:6000, tokenField:'max_tokens', temperature:.1, sendTemperature:true, jsonMode:false, extraParams:{}};
let apiPresets = {};
try { apiPresets = JSON.parse(localStorage.getItem(API_PREFS_KEY) || '{}'); if (!apiPresets || Array.isArray(apiPresets) || typeof apiPresets !== 'object') apiPresets={}; } catch (_) {}
// Convert an old hidden preset to an editable custom configuration.
if (apiPresets.selected==='dots') {
  apiPresets.custom={...apiDefaults,...apiPresets.dots,provider:'custom',endpoint:apiPresets.dots?.endpoint||'',authMode:'api-key',jsonMode:false,extraParams:{chat_template_kwargs:{enable_thinking:false},...(apiPresets.dots?.extraParams||{})}};
  apiPresets.selected=apiPresets.custom.endpoint?'custom':'default';delete apiPresets.dots;
}
let activeProvider = ['default','deepseek','glm','custom'].includes(apiPresets.selected) ? apiPresets.selected : 'default';
let savedAPIProfiles = Array.isArray(apiPresets.saved) ? apiPresets.saved.filter(p=>p && typeof p.id==='string' && typeof p.name==='string' && p.config && typeof p.config==='object') : [];
let apiSecrets = new Map();
let previousAPIIdentity = '';
const configInputs = ['aiModel','aiEndpoint','aiAuthMode','aiAuthHeader','aiMaxTokens','aiTokenField','aiTemperature','aiSendTemperature','aiJSONMode','aiExtraParams'];
function currentAPIIdentity(provider=activeProvider) { return JSON.stringify([provider, provider==='custom'?$('#aiEndpoint').value.trim():provider,$('#aiAuthMode').value,$('#aiAuthHeader').value.trim()]); }
function readAPIConfig() {
  if(activeProvider==='default') return {provider:'default',maxTokens:6000};
  let extraParams;
  try { extraParams=JSON.parse($('#aiExtraParams').value||'{}'); } catch (_) { throw new Error('额外参数必须是有效 JSON，例如 {"top_p":0.9}'); }
  if (!extraParams || Array.isArray(extraParams) || typeof extraParams !== 'object') throw new Error('额外参数必须为 JSON 对象');
  const blocked=['model','messages','stream','temperature','max_tokens','max_completion_tokens','response_format'];
  if(Object.keys(extraParams).some(key=>blocked.includes(key))) throw new Error('额外参数不能覆盖模型、消息和生成设置');
  return {provider:activeProvider,model:$('#aiModel').value.trim(),endpoint:$('#aiEndpoint').value.trim(),authMode:$('#aiAuthMode').value,authHeader:$('#aiAuthHeader').value.trim(),apiKey:$('#aiKey').value,maxTokens:Number($('#aiMaxTokens').value),tokenField:$('#aiTokenField').value,temperature:Number($('#aiTemperature').value),sendTemperature:$('#aiSendTemperature').checked,jsonMode:$('#aiJSONMode').checked,extraParams};
}
function persistAPIConfig() {
  try {
    const {apiKey='',...config}=readAPIConfig();
    apiSecrets.set(previousAPIIdentity,apiKey);
    const identity=currentAPIIdentity();
    if(identity!==previousAPIIdentity) {$('#aiKey').value=apiSecrets.get(identity)||'';previousAPIIdentity=identity;}
    apiPresets[activeProvider]={...config,provider:activeProvider};apiPresets.selected=activeProvider;
    localStorage.setItem(API_PREFS_KEY,JSON.stringify(apiPresets));
    $('#aiConfigStatus').textContent='';
  } catch (error) {$('#aiConfigStatus').textContent=error.message;}
  updateAPIVisibility();
}
function loadAPIPreset() {
  const config={...apiDefaults,...apiPresets[activeProvider]};
  $('#aiProvider').value=activeProvider;
  for(const [id,key] of [['aiModel','model'],['aiEndpoint','endpoint'],['aiAuthMode','authMode'],['aiAuthHeader','authHeader'],['aiMaxTokens','maxTokens'],['aiTokenField','tokenField'],['aiTemperature','temperature']]) $('#'+id).value=config[key];
  $('#aiSendTemperature').checked=config.sendTemperature;$('#aiJSONMode').checked=config.jsonMode;$('#aiExtraParams').value=JSON.stringify(config.extraParams||{},null,2);
  previousAPIIdentity=currentAPIIdentity();$('#aiKey').value=apiSecrets.get(previousAPIIdentity)||'';updateAPIVisibility();
}
function updateAPIVisibility() {
  const builtin=activeProvider==='default';
  $('#aiDefaultNotice').hidden=!builtin;$('#aiCustomIntro').hidden=builtin;$('#aiCustomHint').hidden=builtin;
  $('#aiProfileName').closest('label').hidden=builtin;$('#aiSaveProfile').parentElement.hidden=builtin;
  for(const id of ['aiModel','aiKey','aiAuthMode','aiAuthHeader','aiMaxTokens','aiTokenField','aiTemperature','aiSendTemperature','aiJSONMode','aiExtraParams']) {
    const label=$('#'+id).closest('label');if(label) label.hidden=builtin;
  }
  $('#aiCheckConfig').textContent=builtin?'检查默认服务':'检查地址与参数';
  $('#aiEndpointLabel').hidden=activeProvider!=='custom';$('#aiHeaderLabel').hidden=builtin||$('#aiAuthMode').value!=='custom';
  $('#aiTemperature').disabled=!$('#aiSendTemperature').checked;
  const name=$('#aiProvider').selectedOptions[0]?.textContent||'';
  if(builtin) {$('#aiConfigSummary').textContent='默认 AI 服务 · 无需 API Key';return;}
  $('#aiConfigSummary').textContent=`${name} · ${$('#aiModel').value.trim()||'请在设置中填写模型'} · 密钥仅本页使用`;
}
function clearAPISecrets() {apiSecrets.clear();$('#aiKey').value='';$('#aiConfigStatus').textContent='';}
$('#aiProvider').addEventListener('change',()=>{
  const next=$('#aiProvider').value;
  persistAPIConfig();activeProvider=next;loadAPIPreset();persistAPIConfig();
  pendingAIPlan=[];$('#aiApply').hidden=true;$('#aiPlan').replaceChildren();
});
for(const id of configInputs) $('#'+id).addEventListener('change',persistAPIConfig);
$('#aiKey').addEventListener('input',()=>apiSecrets.set(previousAPIIdentity,$('#aiKey').value));
$('#aiCheckConfig').addEventListener('click',async()=>{
  const generation=identityGeneration,button=$('#aiCheckConfig');button.disabled=true;$('#aiConfigStatus').textContent='正在检查…';
  try {const result=await api('/ai/config/check',{method:'POST',body:JSON.stringify(readAPIConfig())});if(generation===identityGeneration) $('#aiConfigStatus').textContent=result.message;}
  catch(error) {if(generation===identityGeneration) $('#aiConfigStatus').textContent=error.message;}
  finally {button.disabled=false;}
});
document.querySelectorAll('[data-open-settings]').forEach(button=>button.addEventListener('click',()=>{if(!connected)return showAuth();$('#settingsDialog').showModal();}));
loadAPIPreset();

function renderSavedAPIProfiles(selected='') {
  $('#aiSavedProfile').replaceChildren(new Option('选择配置',''),...savedAPIProfiles.map(p=>new Option(p.name,p.id)));
  $('#aiSavedProfile').value=selected;
  $('#aiUpdateProfile').disabled=!selected;$('#aiDeleteProfile').disabled=!selected;
}
function storeSavedAPIProfiles() {
  apiPresets.saved=savedAPIProfiles;
  localStorage.setItem(API_PREFS_KEY,JSON.stringify(apiPresets));
}
function saveNamedAPIProfile(update) {
  try {
    const name=$('#aiProfileName').value.trim();if(!name) throw new Error('请填写配置名称');
    if(!update && savedAPIProfiles.length>=30) throw new Error('最多保存 30 个接口配置');
    persistAPIConfig();const {apiKey,...config}=readAPIConfig();
    const id=update?$('#aiSavedProfile').value:Array.from(crypto.getRandomValues(new Uint8Array(16)),b=>b.toString(16).padStart(2,'0')).join('');
    if(update && !savedAPIProfiles.some(p=>p.id===id)) throw new Error('请先选择已保存配置');
    const profile={id,name,config};savedAPIProfiles=update?savedAPIProfiles.map(p=>p.id===id?profile:p):[...savedAPIProfiles,profile];
    storeSavedAPIProfiles();renderSavedAPIProfiles(id);$('#aiConfigStatus').textContent='配置已保存；密钥仍仅在本页内存中';
  } catch(error) {$('#aiConfigStatus').textContent=error.message;}
}
$('#aiSaveProfile').addEventListener('click',()=>saveNamedAPIProfile(false));
$('#aiUpdateProfile').addEventListener('click',()=>saveNamedAPIProfile(true));
$('#aiSavedProfile').addEventListener('change',()=>{
  const profile=savedAPIProfiles.find(p=>p.id===$('#aiSavedProfile').value);
  if(!profile) return renderSavedAPIProfiles();
  persistAPIConfig();activeProvider=['default','deepseek','glm','custom'].includes(profile.config.provider)?profile.config.provider:'custom';
  const {apiKey,...safeConfig}=profile.config;apiPresets[activeProvider]=safeConfig;
  loadAPIPreset();persistAPIConfig();$('#aiProfileName').value=profile.name;renderSavedAPIProfiles(profile.id);
});
$('#aiDeleteProfile').addEventListener('click',()=>{
  const id=$('#aiSavedProfile').value,profile=savedAPIProfiles.find(p=>p.id===id);
  if(profile && confirm(`删除接口配置“${profile.name}”？不会删除健康记录。`)) {savedAPIProfiles=savedAPIProfiles.filter(p=>p.id!==id);storeSavedAPIProfiles();renderSavedAPIProfiles();$('#aiProfileName').value='';}
});
renderSavedAPIProfiles();
