let workoutEdit = null;
let workoutDraft = [];
function resetWorkoutDraft() {workoutEdit=null;workoutDraft=[];$('#workoutForm').reset();$('#workoutExercises').replaceChildren();$('#workoutError').textContent='';}
function editWorkoutRecord(original=null) {
  resetWorkoutDraft();workoutEdit=original?structuredClone(original):null;workoutDraft=structuredClone(original?.exercises||[]);
  const form=$('#workoutForm');$('#workoutTitle').textContent=original?'编辑训练':'记录训练';
  form.elements.date.value=localDateTime(original?.date??epochForDateKey(selectedDate));form.elements.endDate.value=original?.endDate==null?'':localDateTime(original.endDate);
  form.elements.bodyParts.value=(original?.bodyParts||[]).join('、');form.elements.note.value=original?.note||'';
  renderWorkoutExercises();$('#workoutDialog').showModal();
}
function renderWorkoutExercises() {
  $('#workoutExercises').innerHTML=workoutDraft.map((exercise,i)=>`<section class="exercise-editor"><div class="section-heading"><h3>动作 ${i+1}</h3><button type="button" class="text-button" data-remove-exercise="${i}">移除动作</button></div><div class="form-grid"><label>动作名称<input data-exercise="${i}" data-field="name" value="${escapeAttribute(exercise.name||'')}" required maxlength="100"></label><label>动作部位<input data-exercise="${i}" data-field="bodyPart" value="${escapeAttribute(exercise.bodyPart||'')}" maxlength="100"></label></div>${(exercise.sets||[]).map((set,j)=>`<div class="set-editor"><span>第 ${j+1} 组</span><div class="form-grid">${[['reps','次数','1'],['weight','重量 kg','0.1'],['durationSeconds','时长 秒','1']].map(([key,title,step])=>`<label>${title}<input type="number" min="0" step="${step}" data-exercise="${i}" data-set="${j}" data-field="${key}" value="${set[key]??''}"></label>`).join('')}</div><button class="text-button" type="button" data-remove-set="${i}:${j}">移除这组</button></div>`).join('')}<button class="secondary-button" type="button" data-add-set="${i}">添加组</button></section>`).join('');
}
$('#workoutExercises').addEventListener('input',event=>{
  const input=event.target;if(input.dataset.exercise==null)return;
  const exercise=workoutDraft[Number(input.dataset.exercise)],field=input.dataset.field;
  if(input.dataset.set==null) exercise[field]=input.value;
  else exercise.sets[Number(input.dataset.set)][field]=input.value===''?null:Number(input.value);
});
$('#workoutExercises').addEventListener('click',event=>{
  const button=event.target.closest('button');if(!button)return;
  if(button.dataset.addSet!=null) (workoutDraft[Number(button.dataset.addSet)].sets ||= []).push({reps:null,weight:null,durationSeconds:null});
  if(button.dataset.removeExercise!=null) workoutDraft.splice(Number(button.dataset.removeExercise),1);
  if(button.dataset.removeSet!=null) {const [i,j]=button.dataset.removeSet.split(':').map(Number);workoutDraft[i].sets.splice(j,1);}
  renderWorkoutExercises();
});
$('#addExercise').addEventListener('click',()=>{workoutDraft.push({name:'',bodyPart:'',sets:[]});renderWorkoutExercises();});
$('#newWorkoutRecord').addEventListener('click',()=>editWorkoutRecord());
$('#workoutForm').addEventListener('submit',async event=>{
  event.preventDefault();const form=event.currentTarget,button=form.querySelector('[type=submit]');button.disabled=true;$('#workoutError').textContent='';
  try {
    const date=timestampFromForm(form.elements.date.value,workoutEdit);
    const endDate=form.elements.endDate.value===''?null:(workoutEdit?.endDate!=null&&localDateTime(workoutEdit.endDate)===form.elements.endDate.value?workoutEdit.endDate:new Date(form.elements.endDate.value).getTime()/1000);
    if(!Number.isFinite(date)||(endDate!==null&&(!Number.isFinite(endDate)||endDate<date)))throw new Error('结束时间不能早于开始时间');
    const exercises=workoutDraft.map(exercise=>({...exercise,name:exercise.name.trim(),bodyPart:exercise.bodyPart?.trim()||null,sets:(exercise.sets||[]).map(set=>({...set}))}));
    if(exercises.some(x=>!x.name))throw new Error('请填写每个动作的名称');
    const bodyParts=form.elements.bodyParts.value.split(/[、,，\n]/).map(x=>x.trim()).filter(Boolean);
    await saveAdminActions([recordAction('workout',workoutEdit,{date,endDate,bodyParts,exercises,note:form.elements.note.value.trim()})]);
    $('#workoutDialog').close();resetWorkoutDraft();$('#adminRecordType').value='workout';adminPage=1;renderAdminRows();showToast('训练已保存并同步');
  } catch(error) {$('#workoutError').textContent=error.message;} finally {button.disabled=false;}
});
