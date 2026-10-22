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
require('.volumeAvailableCapacityForImportantUsageKey' in storage and '.volumeAvailableCapacityKey' in storage and '.volumeTotalCapacityKey' in storage, 'Storage display must use iOS volume capacity values with a fallback')
require(not any(x in storage for x in ['UserDefaults', 'URLSession', 'write(', 'Outcome(', 'settle(']), 'Storage display must not persist, export or grade values')
for filename in ['DiagModel.swift', 'SheetPDF.swift', 'Catalog.swift']:
    require('StorageSnapshot' not in (root / 'RefurbX' / filename).read_text(encoding='utf-8'), 'Storage info must be isolated from diagnostic reports')
entitlements = plistlib.loads((root / 'RefurbX/RefurbX.entitlements').read_bytes())
require(entitlements.get('com.apple.developer.nfc.readersession.formats') == ['TAG'], 'Expected NFC TAG only')
for path in (root / 'RefurbX').glob('*.swift'):
    source = path.read_text(encoding='utf-8')
    require(not any(value in source for value in ['DiskProbe', 'readMemory', 'MemoryBoard', '"memory"', 'App-Prefs:', 'App-prefs:', 'prefs:root=', 'settings-navigation://']), f'Obsolete feature or settings URL: {path.name}')
catalog = (root / 'RefurbX/Catalog.swift').read_text(encoding='utf-8')
ids = re.findall(r'Row\(id: "([^"]+)"', catalog)
require(len(ids) == len(set(ids)), 'Duplicate test IDs')
require('light' in ids, 'Expected the light-response check in the catalog')
model = (root / 'RefurbX/DiagModel.swift').read_text(encoding='utf-8')
light = model[model.index('private func startLight()'):model.index('private func enter()')]
require('UIScreen.brightnessDidChangeNotification' in light and 'resetLightReference' in model and 'UIScreen.main.brightness' in light, 'Light check must monitor public screen-brightness changes and allow resetting the reference')
require('Luminosità automatica' in light and 'sensore ambientale' in light and 'requestAccess(for: .video)' not in light and 'SensorKit' not in model, 'Light check must describe a manual auto-brightness observation without camera or direct sensor claims')
guide = (root / 'RefurbX/Guide.swift').read_text(encoding='utf-8')
view = (root / 'RefurbX/DiagView.swift').read_text(encoding='utf-8')
require('Informativa privacy' in view and 'https://refurbx.eu/privacy-policy' in view, 'Missing in-app privacy policy link')
permission_ids = guide.split('static func needsSystemPermission', 1)[1].split('static func line', 1)[0]
for value in ['camera_back', 'camera_front', 'microphone', 'gps', 'compass', 'bluetooth', 'biometrics', 'truedepth', 'lidar']:
    require(f'"{value}"' in permission_ids, f'Missing pre-permission guard: {value}')
require('"nfc"' in permission_ids, 'NFC explanation must lead into the system reader session')
require('NfcTap' not in guide and 'NfcOpenController' not in (root / 'RefurbX/DiagView.swift').read_text(encoding='utf-8'), 'Remove the extra NFC reader button')
require('private func startNfc()' in model and 'tags.beginFromTap()' in model[model.index('private func startNfc()'):model.index('private func nfcActions()')], 'Continue must start NFC reader session')
require('self.showRadioGuide(wifi: true)' in model and 'if !denied { self.showRadioGuide(wifi: false) }' in model, 'Radio-off states must show the in-app instructions')
require('Button("Riprova") { model.retryAfterSettingsGuide() }' in view and 'Button("Salta", role: .cancel) { model.skipCurrent() }' in view, 'Radio instruction alert must provide retry and skip actions')
require(all('Apri lettore tag' not in path.read_text(encoding='utf-8') for path in (root / 'RefurbX').glob('*.swift')), 'Obsolete NFC start label remains')
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
require('UIScreen.brightnessDidChangeNotification' in model and 'originalLightBrightness' in model, 'Light check must observe and restore the original display brightness')
require('NotificationCenter.default.removeObserver(lightBrightnessObserver)' in model and 'UIScreen.main.brightness = originalLightBrightness' in model, 'Light check must remove its observer and restore the original screen brightness')
require('lightPercentage' not in (root / 'RefurbX/Hardware.swift').read_text(encoding='utf-8'), 'Remove the obsolete camera-based light meter')
print(f'PASS: release {info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]}), {len(ids)} test definitions, visible privacy link, radio instructions, NFC auto-start from Continue, M360-style manual auto-brightness check, iOS volume capacity reading, assets and Python syntax. Xcode compilation and device testing remain required.')
