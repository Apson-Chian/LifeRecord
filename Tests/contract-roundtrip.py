"""Actual Kotlin/Swift codecs -> temporary backend -> Swift decoder -> Web JSON.
Run Android :app:testDebugUnitTest first. No sockets, credentials or user stores.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]
fixture=json.loads((root/'Tests/Fixtures/data-contract.json').read_text())
kotlin=root/'Android/app/build/outputs/tests/contract-android.json'
if not kotlin.exists(): raise SystemExit('Run Android :app:testDebugUnitTest first')
with tempfile.TemporaryDirectory(prefix='liferecord-contract-roundtrip-') as folder:
    directory=Path(folder)
    os.environ.update(LIFERECORD_DB=str(directory/'test.sqlite3'), LIFERECORD_IMAGE_DIR=str(directory/'images'), LIFERECORD_SYNC_TOKEN='synthetic-roundtrip-only')
    spec=importlib.util.spec_from_file_location('roundtrip_server',root/'Backend/server.py')
    server=importlib.util.module_from_spec(spec); spec.loader.exec_module(server); server.initialize()
    server.merge_snapshot(fixture['snapshot'])
    server.merge_snapshot(json.loads(kotlin.read_text()))
    response=server.current_snapshot()
    input_file=directory/'server.json'; input_file.write_text(json.dumps(response,ensure_ascii=False))
    swift=root/'iOS'
    sources=['Services/GoalHistory.swift','Services/SyncCompatibility.swift','Services/RecordInput.swift','Services/SyncModels.swift','Services/WorkoutDetails.swift']
    executable=directory/'codec'
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(directory/'cache'),*[str(swift/'LifeRecord'/s) for s in sources],str(swift/'Tests/data-contract.swift'),'-o',str(executable)],check=True)
    output=directory/'swift.json'
    subprocess.run([str(executable),str(output),str(input_file)],cwd=swift,check=True)
    server.merge_snapshot(json.loads(output.read_text()))
    result=server.current_snapshot()
    # Unknown fields, absent arrays and explicit null survive the typed-client path.
    for key,value in fixture['snapshot'].items():
        if result[key]!=value: raise AssertionError(f'cross-codec difference: {key}')
    web=json.loads(subprocess.check_output(['node','-e','let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>process.stdout.write(JSON.stringify(JSON.parse(s))))'],input=json.dumps(result).encode()))
    if web!=result: raise AssertionError('Web JSON round-trip changed the backend response')
print('PASS: real Kotlin and Swift codecs, temporary backend and Web JSON preserve shared records and extensions')
