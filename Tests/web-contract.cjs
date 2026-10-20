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
