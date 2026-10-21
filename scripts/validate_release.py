"""Release preflight. Run locally or before XcodeGen on Codemagic."""
from pathlib import Path
import ast
import json
import plistlib
import re

root = Path(__file__).resolve().parents[1]
def require(condition, message):
    if not condition:
        raise SystemExit(message)

info = plistlib.loads((root / 'RefurbX/Info.plist').read_bytes())
project = (root / 'project.yml').read_text(encoding='utf-8')
require(f'MARKETING_VERSION: "{info["CFBundleShortVersionString"]}"' in project, 'Version mismatch')
require(f'CURRENT_PROJECT_VERSION: "{info["CFBundleVersion"]}"' in project, 'Build number mismatch')
privacy = plistlib.loads((root / 'RefurbX/PrivacyInfo.xcprivacy').read_bytes())
require(any(x['NSPrivacyAccessedAPIType'] == 'NSPrivacyAccessedAPICategoryUserDefaults' and 'CA92.1' in x['NSPrivacyAccessedAPITypeReasons'] for x in privacy['NSPrivacyAccessedAPITypes']), 'Missing UserDefaults reason')
require(any(x['NSPrivacyAccessedAPIType'] == 'NSPrivacyAccessedAPICategoryDiskSpace' and x['NSPrivacyAccessedAPITypeReasons'] == ['85F4.1'] for x in privacy['NSPrivacyAccessedAPITypes']), 'Missing display-only disk space reason')
storage = (root / 'RefurbX/StorageInfo.swift').read_text(encoding='utf-8')
require('.volumeTotalCapacityKey' in storage and '.volumeAvailableCapacityKey' in storage, 'Missing public volume API')
require(not any(x in storage for x in ['UserDefaults', 'URLSession', 'write(', 'Outcome(', 'settle(']), 'Storage display must not persist, export or grade values')
for filename in ['DiagModel.swift', 'SheetPDF.swift', 'Catalog.swift']:
    require('StorageSnapshot' not in (root / 'RefurbX' / filename).read_text(encoding='utf-8'), 'Storage info must be isolated from diagnostic reports')
entitlements = plistlib.loads((root / 'RefurbX/RefurbX.entitlements').read_bytes())
require(entitlements.get('com.apple.developer.nfc.readersession.formats') == ['TAG'], 'Expected NFC TAG only')
for path in (root / 'RefurbX').glob('*.swift'):
    source = path.read_text(encoding='utf-8')
    require(not any(value in source for value in ['DiskProbe', 'readMemory', '"memory"', 'App-Prefs:', 'App-prefs:', 'prefs:root=', 'settings-navigation://']), f'Obsolete feature or settings URL: {path.name}')
catalog = (root / 'RefurbX/Catalog.swift').read_text(encoding='utf-8')
ids = re.findall(r'Row\(id: "([^"]+)"', catalog)
require(len(ids) == len(set(ids)), 'Duplicate test IDs')
require('Luminosità automatica (manuale)' in catalog, 'Light test must be labelled manual')
model = (root / 'RefurbX/DiagModel.swift').read_text(encoding='utf-8')
light = model.split('    private func startLight() {', 1)[1].split('    private func watchProximity()', 1)[0]
require('camera.' not in light and 'settle(' not in light, 'Manual light test must not generate automatic results')
require('sensore non misurato' in light, 'Missing manual light limitation')
guide = (root / 'RefurbX/Guide.swift').read_text(encoding='utf-8')
permission_ids = guide.split('static func needsSystemPermission', 1)[1].split('static func line', 1)[0]
for value in ['camera_back', 'camera_front', 'microphone', 'gps', 'compass', 'bluetooth', 'biometrics', 'truedepth', 'lidar']:
    require(f'"{value}"' in permission_ids, f'Missing pre-permission guard: {value}')
for path in root.glob('scripts/*.py'):
    ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
for path in (root / 'RefurbX/Assets.xcassets').rglob('Contents.json'):
    data = json.loads(path.read_text(encoding='utf-8'))
    for item in data.get('images', []):
        if item.get('filename'):
            require((path.parent / item['filename']).is_file(), f'Missing asset: {path}')
require('guard outboxEnabled, !outcomes.isEmpty' in model, 'Cable export requires Send consent')
require('"touchPoints": 5' not in model, 'Do not export an unmeasured touch-point count')
require('row.note.prefix(140)' not in (root / 'RefurbX/SheetPDF.swift').read_text(encoding='utf-8'), 'Report must preserve complete notes')
print(f'PASS: release {info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]}), {len(ids)} test definitions, privacy, NFC, assets and Python syntax. Xcode compilation and device testing remain required.')
