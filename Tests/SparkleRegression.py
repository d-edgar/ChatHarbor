"""Validate the built updater configuration (run after xcodebuild)."""
import base64
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
with (app / 'Contents/Info.plist').open('rb') as file:
    info = plistlib.load(file)
assert info['SUEnableAutomaticChecks'] is True
assert info['SUAutomaticallyUpdate'] is False
assert info['SUAllowsAutomaticUpdates'] is False, 'Every installation must require approval'
assert info['SUEnableInstallerLauncherService'] is True
assert info.get('SUEnableDownloaderService', False) is False
assert info['SUVerifyUpdateBeforeExtraction'] is True
assert info['SURequireSignedFeed'] is True
assert info['SUEnableSystemProfiling'] is False
assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32
assert info['SUFeedURL'] == 'https://github.com/d-edgar/ChatHarbor/releases/latest/download/appcast.xml'
assert info['CFBundleVersion'] == info['CFBundleShortVersionString'], 'Build version must advance with releases'
framework = app / 'Contents/Frameworks/Sparkle.framework'
for helper in ['XPCServices/Installer.xpc', 'Autoupdate', 'Updater.app']:
    assert (framework / 'Versions/B' / helper).exists(), f'Missing updater helper: {helper}'
print('PASS: built update policy, signing key, release numbering, feed and installer helpers')

# Public RFC 8032 test vector: exercise CI key matching without production secrets.
import subprocess
import tempfile
seed = base64.b64encode(bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'))
public = base64.b64encode(bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')).decode()
with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory) / 'Info.plist'
    fixture.write_bytes(plistlib.dumps({'SUPublicEDKey': public}))
    checker = Path(__file__).resolve().parent.parent / 'scripts/verify-sparkle-key.swift'
    for value, expected in [(seed, 0), (b'', 1), (base64.b64encode(bytes(32)), 1)]:
        result = subprocess.run(['swift', str(checker), str(fixture)], input=value, capture_output=True)
        assert result.returncode == expected, 'Signing-key preflight failed its test vector'
print('PASS: matching key accepted; missing and mismatched keys rejected')
