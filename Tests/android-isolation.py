"""Fail closed before installing an instrumentation target; inspects the actual APK."""
import argparse
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('apk', type=Path)
args = parser.parse_args()
def require(condition, message):
    if not condition:
        raise SystemExit(message)
sdk = Path(next(line.split('=', 1)[1] for line in
    (root / 'Android/local.properties').read_text().splitlines() if line.startswith('sdk.dir=')))
aapt = sorted((sdk / 'build-tools').glob('*/aapt2'))[-1]
badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(args.apk)], text=True)
package = re.search(r"package: name='([^']+)'", badging).group(1)
require(package == 'ltd.apsonchian.liferecord.instrumented', f'UNSAFE test target package: {package}')
require("uses-permission: name='android.permission.INTERNET'" not in badging, 'UNSAFE: target has INTERNET permission')
xml = subprocess.check_output([str(aapt), 'dump', 'xmltree', str(args.apk), '--file', 'AndroidManifest.xml'], text=True)
require('IsolatedLifeRecordApplication' in xml, 'UNSAFE: fake application is not installed')
require('sharedUserId' not in xml, 'UNSAFE: shared UID defeats package isolation')
print('PASS: APK has independent applicationId, fake application, no INTERNET and no shared UID')
