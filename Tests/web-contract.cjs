// The same synthetic wire samples used by Python, Kotlin and Swift.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'Fixtures/data-contract.json')));
const source = fs.readFileSync(path.join(__dirname, '../Web/app.js'), 'utf8');
// Exercise the actual form limit expression without launching a network-capable UI.
const expression = source.match(/if \((files.length \+ retainedPhotoIDs.length > [^)]+)\) throw new Error\("每餐合计最多保存/)[1];
for (const count of [0, 6, 7, 12, 13]) {
  const exceeds=vm.runInNewContext(expression, {files:[],retainedPhotoIDs:Array(count),MAX_MEAL_PHOTOS:12});
  assert.equal(exceeds, count > 12, `photo count ${count}`);
}
const copy=JSON.parse(JSON.stringify(fixture.snapshot));
assert.deepEqual(copy,fixture.snapshot);
assert.equal(copy.meals[0].photoIDs.length,12);
assert.equal(copy.bodyMetrics[0].waist,null);
assert.equal(copy.meals[0].extension.origin,'must survive');
assert.equal(Object.hasOwn(copy.workoutEntries[0],'bodyParts'),false);
console.log('PASS: Web photo limit uses shared sample; JSON preserves extensions, missing fields, null and arrays');
const goalFunction=source.match(/function goals\(day\) \{[\s\S]*?\n\}/)[0];
const goalProfile={proteinGoal:180,goalHistory:[{id:'baseline',effectiveDate:'1970-01-01',updatedAt:0,proteinGoal:100},{id:'new',effectiveDate:'2026-10-22',updatedAt:10,proteinGoal:180}]};
const goalContext=vm.createContext({state:{settings:goalProfile},defaultSettings:{}});
vm.runInContext(goalFunction,goalContext);
assert.equal(vm.runInContext("goals('2026-10-21').proteinGoal",goalContext),100);
assert.equal(vm.runInContext("goals('2026-10-22').proteinGoal",goalContext),180);
assert.equal(vm.runInContext("goals('2026-10-23').proteinGoal",goalContext),180);
assert.equal(vm.runInContext("goals().proteinGoal",goalContext),180);
console.log('PASS: actual Web resolver preserves prior-day targets and uses new targets from effective day');

const oldVersion={...goalProfile.goalHistory[1]};
goalProfile.goalHistory.push({...oldVersion,effectiveDate:'2026-10-20',proteinGoal:130,revisionAt:20,revisionID:'revision-a'});
assert.equal(vm.runInContext("goals('2026-10-21').proteinGoal",goalContext),130);
assert.equal(vm.runInContext("goals('2026-10-22').proteinGoal",goalContext),130);
goalProfile.goalHistory.push(oldVersion);
assert.equal(vm.runInContext("goals('2026-10-22').proteinGoal",goalContext),130);
goalProfile.goalHistory.push({...goalProfile.goalHistory[0],proteinGoal:90,revisionAt:30,revisionID:'baseline-edit'});
assert.equal(vm.runInContext("goals('2026-10-19').proteinGoal",goalContext),90);
console.log('PASS: Web uses stable-ID corrections, moved dates and corrected baseline despite stale replay');
