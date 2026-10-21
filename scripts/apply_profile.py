import base64
import glob
import json
import os
import plistlib
import re
import shlex
import struct
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

NFC_KEY = "com.apple.developer.nfc.readersession.formats"
BUNDLE = "eu.refurbx.diagnostics"
TEAM = "L9F47LJC86"
ENTITLEMENTS_REL = "RefurbX/RefurbX.entitlements"
MISSING_TAG = (
    "La build è firmata senza il permesso NFC TAG. "
    "L'iPhone mostrerebbe «Missing required entitlement». Pubblicazione interrotta."
)
NO_PROFILE_TAG = (
    "Il profilo App Store su Codemagic non include il permesso NFC TAG, "
    "quindi l'iPhone continuerà a dire che manca il permesso. "
    "Su Identifiers lascia attivo NFC Tag Reading, senza NDEF, e rilancia la build: "
    "il profilo vecchio viene cancellato e ricreato. "
    "The App Store profile on Codemagic does not include the NFC TAG entitlement, "
    "so the phone will keep saying the permission is missing."
)
BUNDLE_RESOURCE_FALLBACK = "85QFC4DYNF"
STALE_PROFILE_IDS = ("59JK5D8P4K",)


def fail(message):
    sys.exit(message)


def project_root():
    return Path(os.environ.get("CM_BUILD_DIR") or ".").resolve()


def nfc_formats(entitlements):
    raw = entitlements.get(NFC_KEY, [])
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, (list, tuple)):
        return [str(item) for item in raw]
    return []


def tag_only(entitlements):
    return nfc_formats(entitlements) == ["TAG"]


def contains_tag(entitlements):
    return "TAG" in nfc_formats(entitlements)


def is_ios_profile(data):
    platforms = data.get("Platform")
    if platforms is None:
        return True
    if isinstance(platforms, str):
        return platforms == "iOS"
    if isinstance(platforms, (list, tuple)):
        return "iOS" in platforms
    return True


def not_expired(data):
    exp = data.get("ExpirationDate")
    if not isinstance(exp, datetime):
        return True
    now = datetime.now(exp.tzinfo) if exp.tzinfo else datetime.now()
    return exp > now


def is_app_store(data):
    if data.get("ProvisionedDevices"):
        return False
    if data.get("ProvisionsAllDevices") is True:
        return False
    entitlements = data.get("Entitlements") or {}
    if entitlements.get("get-task-allow") is True:
        return False
    return is_ios_profile(data) and not_expired(data)


def provisioning_profiles():
    homes = [
        os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
        os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
    ]
    paths = []
    for home in homes:
        paths.extend(glob.glob(os.path.join(home, "*.mobileprovision")))
    found = []
    seen = set()
    for path in paths:
        data = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", path]))
        app_id = data.get("Entitlements", {}).get("application-identifier", "")
        if str(app_id).partition(".")[2] != BUNDLE:
            continue
        uuid = str(data.get("UUID") or path)
        if uuid in seen:
            continue
        seen.add(uuid)
        found.append((path, data))
    return found


def describe_profile(data):
    formats = nfc_formats(data.get("Entitlements", {}))
    kind = "App Store" if is_app_store(data) else "non App Store"
    has = "sì" if "TAG" in formats else "no"
    return (
        f"Profilo trovato: {data.get('Name')} uuid={data.get('UUID')} ({kind}) "
        f"contiene NFC TAG: {has} formati={formats}"
    )


def choose_profile(found):
    entitlements = project_root() / ENTITLEMENTS_REL
    if not entitlements.exists():
        fail("Manca RefurbX.entitlements. Pubblicazione interrotta.")
    try:
        parsed = plistlib.loads(entitlements.read_bytes())
    except Exception:
        parsed = {}
    if not tag_only(parsed):
        fail(
            "RefurbX.entitlements deve contenere solo TAG, senza NDEF. "
            "Pubblicazione interrotta."
        )
    for _path, data in found:
        print(describe_profile(data))
    tagged = [
        item
        for item in found
        if is_app_store(item[1]) and contains_tag(item[1].get("Entitlements", {}))
    ]
    if not tagged:
        fail(NO_PROFILE_TAG)

    def rank(item):
        formats = nfc_formats(item[1].get("Entitlements", {}))
        exact = set(formats) == {"TAG"}
        created = item[1].get("CreationDate")
        if isinstance(created, datetime):
            stamp = created.timestamp()
        else:
            stamp = 0
        return (exact, stamp)

    tagged.sort(key=rank)
    return tagged[-1]


def der_bytes(value):
    if isinstance(value, (bytes, bytearray)):
        return bytes(value)
    data = getattr(value, "data", None)
    if isinstance(data, (bytes, bytearray)):
        return bytes(data)
    fail("Il certificato nel profilo non è leggibile. Pubblicazione interrotta.")


def certificate_identity(profile):
    certs = profile.get("DeveloperCertificates") or []
    if not certs:
        fail("Il profilo non contiene un certificato di distribuzione. Pubblicazione interrotta.")
    proc = subprocess.run(
        [
            "openssl",
            "x509",
            "-inform",
            "DER",
            "-noout",
            "-subject",
            "-nameopt",
            "RFC2253",
            "-fingerprint",
            "-sha1",
        ],
        input=der_bytes(certs[0]),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        fail("Non leggo il certificato dentro il profilo. Pubblicazione interrotta.")
    subject = ""
    fingerprint = ""
    for line in proc.stdout.decode().splitlines():
        if line.lower().startswith("subject="):
            subject = line.split("=", 1)[1]
        elif "fingerprint=" in line.lower():
            fingerprint = line.split("=", 1)[1].strip().replace(":", "").upper()
    name = common_name(subject)
    if "Distribution" not in name:
        fail("Il profilo non è firmato con Apple Distribution. Pubblicazione interrotta.")
    if len(fingerprint) != 40:
        fail("Impronta del certificato non valida. Pubblicazione interrotta.")
    return fingerprint, name


def common_name(subject):
    parts = []
    current = []
    escaped = False
    for char in subject:
        if escaped:
            current.append(char)
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char == ",":
            parts.append("".join(current).strip())
            current = []
            continue
        current.append(char)
    parts.append("".join(current).strip())
    for part in parts:
        if part.startswith("CN="):
            return part[3:]
    return ""


def pbx_quote(value):
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def iter_build_settings(text):
    needle = "buildSettings = {"
    start = 0
    while True:
        idx = text.find(needle, start)
        if idx < 0:
            return
        depth = 1
        cursor = idx + len(needle)
        while cursor < len(text) and depth:
            char = text[cursor]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
            cursor += 1
        end = cursor
        if end < len(text) and text[end] == ";":
            end += 1
        yield idx, end
        start = end


def set_setting(block, key, value, indent):
    pattern = re.compile(rf"^([ \t]*){re.escape(key)} = .*;$", re.M)
    if pattern.search(block):
        return pattern.sub(rf"\1{key} = {value};", block, count=1)
    needle = f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};"
    insertion = needle + f"\n{indent}{key} = {value};"
    if needle not in block:
        return block
    return block.replace(needle, insertion, 1)


def patch_build_settings(text, uuid, name, identity):
    text = text.replace("CODE_SIGN_STYLE = Automatic;", "CODE_SIGN_STYLE = Manual;")
    sdk_line = re.compile(
        r'^[ \t]*"?(?:CODE_SIGN_IDENTITY|PROVISIONING_PROFILE_SPECIFIER|PROVISIONING_PROFILE)\[sdk=[^\]]*\]"?[ \t]*=[ \t]*[^;]*;[ \t]*\n',
        re.M,
    )
    pieces = []
    cursor = 0
    for start, end in iter_build_settings(text):
        pieces.append(text[cursor:start])
        block = text[start:end]
        if f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};" in block:
            block = sdk_line.sub("", block)
            indent_match = re.search(r"^([ \t]*)PRODUCT_BUNDLE_IDENTIFIER = ", block, re.M)
            indent = indent_match.group(1) if indent_match else "\t\t\t\t"
            settings = [
                ("CODE_SIGN_STYLE", "Manual"),
                ("CODE_SIGN_IDENTITY", pbx_quote(identity)),
                ("DEVELOPMENT_TEAM", TEAM),
                ("PROVISIONING_PROFILE", pbx_quote(uuid)),
                ("PROVISIONING_PROFILE_SPECIFIER", pbx_quote(uuid)),
                ("CODE_SIGN_ENTITLEMENTS", ENTITLEMENTS_REL),
                ("OTHER_CODE_SIGN_FLAGS", pbx_quote("--generate-entitlement-der")),
            ]
            for key, value in settings:
                block = set_setting(block, key, value, indent)
        pieces.append(block)
        cursor = end
    pieces.append(text[cursor:])
    patched = "".join(pieces)
    if f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};" not in patched:
        fail("Bundle id non trovato nel progetto Xcode")
    if "CODE_SIGN_ENTITLEMENTS = RefurbX/RefurbX.entitlements;" not in patched:
        fail("CODE_SIGN_ENTITLEMENTS non è nel progetto Xcode. Pubblicazione interrotta.")
    if f"PROVISIONING_PROFILE_SPECIFIER = {pbx_quote(uuid)};" not in patched:
        fail("Il progetto Xcode non usa il profilo con NFC TAG. Pubblicazione interrotta.")
    return patched


def write_export_options(uuid, name, identity):
    # XML, not binary: exportArchive re-signs from this file. The value is the
    # profile UUID so a second ios_app_store profile with the same bundle id
    # cannot be chosen. CODE_SIGN_ENTITLEMENTS is applied at archive time.
    payload = {
        "method": "app-store",
        "teamID": TEAM,
        "signingStyle": "manual",
        "signingCertificate": identity,
        "provisioningProfiles": {BUNDLE: uuid},
        "uploadSymbols": True,
    }
    destination = Path.home().joinpath("export_options.plist")
    with destination.open("wb") as handle:
        plistlib.dump(payload, handle, fmt=plistlib.FMT_XML)
    loaded = plistlib.loads(destination.read_bytes())
    if loaded.get("provisioningProfiles", {}).get(BUNDLE) != uuid:
        fail("export_options.plist non punta al profilo con NFC TAG. Pubblicazione interrotta.")
    if loaded.get("signingCertificate") != identity:
        fail("export_options.plist non firma con lo stesso certificato del profilo. Pubblicazione interrotta.")
    if loaded.get("signingStyle") != "manual":
        fail("export_options.plist non usa la firma manuale. Pubblicazione interrotta.")
    if loaded.get("method") != "app-store":
        fail("export_options.plist non esporta per App Store. Pubblicazione interrotta.")
    print(f"Export: certificato {identity}, profilo {name} uuid={uuid}, entitlements {ENTITLEMENTS_REL}")


def write_xcargs(uuid, _name, identity):
    entitlements = str(project_root() / ENTITLEMENTS_REL)
    parts = [
        "COMPILER_INDEX_STORE_ENABLE=NO",
        "CODE_SIGN_STYLE=Manual",
        "CODE_SIGN_ENTITLEMENTS=" + shlex.quote(entitlements),
        "OTHER_CODE_SIGN_FLAGS=" + shlex.quote("--generate-entitlement-der"),
        f"DEVELOPMENT_TEAM={TEAM}",
        "CODE_SIGN_IDENTITY=" + shlex.quote(identity),
        "PROVISIONING_PROFILE=" + shlex.quote(uuid),
        "PROVISIONING_PROFILE_SPECIFIER=" + shlex.quote(uuid),
    ]
    text = " ".join(parts)
    # xcode-project build-ipa splits this string with shlex. The round-trip
    # must keep the entitlements path and the profile name as single arguments.
    parsed = shlex.split(text)
    joined = " ".join(parsed)
    if entitlements not in joined or uuid not in joined or identity not in joined:
        fail("Gli argomenti di firma dell'archivio non includono il permesso NFC TAG.")
    if "--generate-entitlement-der" not in joined:
        fail("Gli argomenti di firma non generano gli entitlement DER che iOS legge.")
    Path("/tmp/refurbx-archive-xcargs.txt").write_text(text + "\n")


def install_profile(path, uuid):
    blob = Path(path).read_bytes()
    homes = [
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    ]
    for folder in homes:
        folder.mkdir(parents=True, exist_ok=True)
        (folder / f"{uuid}.mobileprovision").write_bytes(blob)
    Path("/tmp/refurbx-tag.mobileprovision").write_bytes(blob)


def profile_homes():
    return [
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    ]


def quarantine_other_profiles(keep_uuid):
    ignored = Path("/tmp/refurbx-ignored-profiles")
    ignored.mkdir(parents=True, exist_ok=True)
    kept = []
    for folder in profile_homes():
        if not folder.is_dir():
            continue
        for path in list(folder.glob("*.mobileprovision")):
            try:
                data = load_profile(path)
            except Exception:
                destination = ignored / path.name
                if destination.exists():
                    destination.unlink()
                path.replace(destination)
                print(f"Profilo ignorato, non leggibile: {path.name}")
                continue
            uuid = str(data.get("UUID") or "")
            entitlements = data.get("Entitlements") or {}
            name = data.get("Name")
            formats = nfc_formats(entitlements)
            if uuid == keep_uuid and contains_tag(entitlements):
                kept.append(f"{name} uuid={uuid}")
                continue
            destination = ignored / f"{uuid or path.stem}.mobileprovision"
            if destination.exists():
                destination.unlink()
            path.replace(destination)
            print(
                f"Profilo ignorato: {name} uuid={uuid} "
                f"contiene NFC TAG: {'sì' if 'TAG' in formats else 'no'} formati={formats}"
            )
    if not kept:
        fail(NO_PROFILE_TAG)
    print("Profilo rimasto per la firma: " + ", ".join(kept))


def profile_team(profile):
    teams = profile.get("TeamIdentifier") or []
    if isinstance(teams, str) and teams:
        return teams
    if isinstance(teams, (list, tuple)) and teams:
        return str(teams[0])
    return TEAM


def prepare():
    global TEAM
    path, chosen = choose_profile(provisioning_profiles())
    uuid = str(chosen["UUID"])
    name = chosen["Name"]
    formats = nfc_formats(chosen.get("Entitlements", {}))
    has_tag = "TAG" in formats
    identity, cert_name = certificate_identity(chosen)
    TEAM = profile_team(chosen)
    print(f"Profilo scelto: {name}")
    print(f"UUID profilo scelto: {uuid}")
    print(f"Team del profilo: {TEAM}")
    print(f"Il profilo contiene NFC TAG: {'sì' if has_tag else 'no'} formati={formats}")
    print(f"Certificato di distribuzione: {cert_name} {identity}")
    if not has_tag:
        fail(NO_PROFILE_TAG)
    install_profile(path, uuid)
    stable = Path("/tmp/refurbx-tag.mobileprovision")
    Path("/tmp/refurbx-profile-uuid.txt").write_text(uuid + "\n")
    Path("/tmp/refurbx-profile-name.txt").write_text(name + "\n")
    Path("/tmp/refurbx-profile-path.txt").write_text(str(stable) + "\n")
    Path("/tmp/refurbx-profile-has-tag.txt").write_text("sì\n")
    Path("/tmp/refurbx-sign-identity.txt").write_text(identity + "\n")
    quarantine_other_profiles(uuid)
    project = project_root() / "RefurbX.xcodeproj/project.pbxproj"
    project.write_text(patch_build_settings(project.read_text(), uuid, name, identity))
    write_export_options(uuid, name, identity)
    write_xcargs(uuid, name, identity)


def extract_plist_bytes(data):
    if not data:
        return b""
    starts = [pos for pos in (data.find(b"<?xml"), data.find(b"<plist"), data.find(b"bplist00")) if pos >= 0]
    if not starts:
        return data
    raw = data[min(starts) :]
    if raw.startswith(b"<?xml") or raw.startswith(b"<plist"):
        end = raw.find(b"</plist>")
        if end >= 0:
            raw = raw[: end + len(b"</plist>")]
    return raw


def parse_entitlements_blob(data):
    raw = extract_plist_bytes(data)
    if not raw:
        return None
    try:
        parsed = plistlib.loads(raw)
    except Exception:
        return None
    if isinstance(parsed, dict):
        return parsed
    return None


def codesign_output(app, args):
    proc = subprocess.run(
        ["codesign", "-d", *args, str(app)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return proc.returncode, proc.stdout, proc.stderr


def dash_colon_blob(app):
    _code, out, err = codesign_output(app, ["--entitlements", ":-"])
    combined = out + b"\n" + err
    return combined, extract_plist_bytes(combined)


def blob_claims_tag(blob):
    raw = extract_plist_bytes(blob)
    if b"TAG" not in raw or NFC_KEY.encode() not in raw:
        return False
    parsed = parse_entitlements_blob(raw)
    if not isinstance(parsed, dict):
        return False
    return tag_only(parsed)


def der_slot_present(text):
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("-7="):
            continue
        value = stripped.split("=", 1)[1].strip().lower()
        if value and any(char in "123456789abcdef" for char in value):
            return True
    return False


def signature_verbose(app):
    _code, out, err = codesign_output(app, ["-vvv"])
    return (out + err).decode("utf-8", "ignore")


def main_executable(app):
    app = Path(app)
    info = app / "Info.plist"
    name = app.stem
    if info.exists():
        try:
            parsed = plistlib.load(info.open("rb"))
            name = str(parsed.get("CFBundleExecutable") or name)
        except Exception:
            pass
    return app / name


def mach_slice(data):
    if len(data) < 8:
        return data
    magic = struct.unpack(">I", data[:4])[0]
    if magic != 0xCAFEBABE:
        return data
    count = struct.unpack(">I", data[4:8])[0]
    fallback = data
    for index in range(count):
        start = 8 + index * 20
        cputype, _subtype, offset, size, _align = struct.unpack(">5I", data[start : start + 20])
        chunk = data[offset : offset + size]
        fallback = chunk
        if cputype == 0x0100000C:
            return chunk
    return fallback


def der_entitlement_bytes(app):
    binary = main_executable(app)
    if not binary.is_file():
        print(f"Eseguibile assente: {binary}")
        return b""
    data = mach_slice(binary.read_bytes())
    if len(data) < 32 or struct.unpack("<I", data[:4])[0] != 0xFEEDFACF:
        print("Il binario non è un Mach-O arm64.")
        return b""
    command_count = struct.unpack("<I", data[16:20])[0]
    cursor = 32
    signature_offset = None
    signature_size = None
    for _ in range(command_count):
        if cursor + 8 > len(data):
            break
        command, size = struct.unpack_from("<II", data, cursor)
        if command == 0x1D and cursor + 16 <= len(data):
            signature_offset, signature_size = struct.unpack_from("<II", data, cursor + 8)
        if size < 8:
            break
        cursor += size
    if signature_offset is None or signature_size is None:
        print("LC_CODE_SIGNATURE assente.")
        return b""
    blob = data[signature_offset : signature_offset + signature_size]
    if len(blob) < 12 or struct.unpack(">I", blob[:4])[0] != 0xFADE0CC0:
        print("Superblob della firma assente.")
        return b""
    count = struct.unpack(">I", blob[8:12])[0]
    for index in range(count):
        slot_type, slot_offset = struct.unpack_from(">II", blob, 12 + index * 8)
        if slot_type != 7:
            continue
        if slot_offset + 8 > len(blob):
            print("Slot DER 7 troncato.")
            return b""
        inner_length = struct.unpack_from(">I", blob, slot_offset + 4)[0]
        end = slot_offset + inner_length if 8 < inner_length <= len(blob) - slot_offset else min(len(blob), slot_offset + 65536)
        return blob[slot_offset:end]
    print("Slot DER 7 assente. iOS non legge il permesso NFC da lì.")
    return b""


def der_claims_tag(app):
    payload = der_entitlement_bytes(app)
    key = NFC_KEY.encode()
    found = payload.find(key)
    if found < 0:
        print(f"Nel permesso DER manca {NFC_KEY}. Byte letti: {len(payload)}.")
        return False
    window = payload[found : found + len(key) + 80]
    if b"NDEF" in window:
        print("Il permesso DER contiene NDEF. App Store Connect lo rifiuta con 90778.")
        return False
    if b"TAG" not in window:
        print("Il permesso DER contiene la chiave NFC ma non il valore TAG.")
        return False
    print(f"Permesso DER: NFC TAG presente, {len(payload)} byte nello slot 7.")
    return True


def load_profile(path):
    return plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(path)]))


def embedded_has_tag(app):
    embedded = Path(app) / "embedded.mobileprovision"
    if not embedded.exists():
        return False, ""
    try:
        data = load_profile(embedded)
    except Exception:
        return False, ""
    name = str(data.get("Name") or "")
    return contains_tag(data.get("Entitlements", {})), name


def expand_team_value(value):
    if isinstance(value, str):
        if value.endswith(".*"):
            return f"{TEAM}.{BUNDLE}"
        return value
    if isinstance(value, list):
        return [expand_team_value(item) for item in value]
    return value


def declared_entitlements():
    path = project_root() / ENTITLEMENTS_REL
    parsed = plistlib.load(path.open("rb"))
    if not tag_only(parsed):
        fail(
            "RefurbX.entitlements deve contenere solo TAG, senza NDEF. "
            "Pubblicazione interrotta."
        )
    return parsed


def signature_entitlements(app, profile):
    declared_entitlements()
    _raw, blob = dash_colon_blob(app)
    current = parse_entitlements_blob(blob) or {}
    allowed = profile.get("Entitlements") or {}
    merged = {}
    for key, value in current.items():
        if key in (NFC_KEY, "get-task-allow"):
            continue
        merged[key] = value
    for key in ("application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups"):
        if key not in merged and key in allowed:
            merged[key] = expand_team_value(allowed[key])
    merged.pop("get-task-allow", None)
    team = profile_team(profile)
    allowed_app = allowed.get("application-identifier")
    if isinstance(allowed_app, str) and allowed_app and "*" not in allowed_app:
        merged["application-identifier"] = allowed_app
    else:
        merged["application-identifier"] = f"{team}.{BUNDLE}"
    merged["com.apple.developer.team-identifier"] = team
    if "beta-reports-active" not in merged:
        merged["beta-reports-active"] = True
    merged[NFC_KEY] = ["TAG"]
    if not tag_only(merged):
        fail(MISSING_TAG)
    return merged


def resign(app, identity, profile_path, profile):
    if not contains_tag(profile.get("Entitlements", {})):
        fail(MISSING_TAG)
    merged = signature_entitlements(app, profile)
    embedded = Path(app) / "embedded.mobileprovision"
    embedded.write_bytes(Path(profile_path).read_bytes())
    ent_path = Path("/tmp/refurbx-export.entitlements")
    with ent_path.open("wb") as handle:
        plistlib.dump(merged, handle, fmt=plistlib.FMT_XML)
    commands = [
        [
            "codesign",
            "--force",
            "--sign",
            identity,
            "--entitlements",
            str(ent_path),
            "--generate-entitlement-der",
            "--timestamp",
            str(app),
        ],
        [
            "codesign",
            "--force",
            "--sign",
            identity,
            "--entitlements",
            str(ent_path),
            "--generate-entitlement-der",
            str(app),
        ],
    ]
    last_error = None
    for cmd in commands:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if proc.returncode == 0:
            return
        last_error = proc.stdout
        if "--timestamp" in cmd:
            continue
        break
    print(last_error or "")
    fail("Non riesco a rifirmare l'app con il permesso NFC TAG. Pubblicazione interrotta.")


def expected_profile_uuid():
    path = Path("/tmp/refurbx-profile-uuid.txt")
    if not path.exists():
        return ""
    return path.read_text().strip()


def app_is_tagged(app):
    raw_dump, blob = dash_colon_blob(app)
    print("Entitlements firmati (codesign -d --entitlements :-):")
    print(raw_dump.decode("utf-8", "ignore"))
    if b"NDEF" in blob:
        print("La firma contiene NDEF. App Store Connect la rifiuta con l'errore 90778.")
        return False
    if not blob_claims_tag(blob):
        print("codesign -d --entitlements :- non contiene TAG.")
        return False
    if not der_claims_tag(app):
        print("Gli entitlement DER che iOS legge non contengono TAG.")
        return False
    embedded = Path(app) / "embedded.mobileprovision"
    if not embedded.exists():
        print("Profilo dentro l'app assente.")
        return False
    try:
        data = load_profile(embedded)
    except Exception:
        print("Profilo dentro l'app non leggibile.")
        return False
    name = str(data.get("Name") or "")
    uuid = str(data.get("UUID") or "")
    formats = nfc_formats(data.get("Entitlements") or {})
    tagged = "TAG" in formats
    print(f"Profilo dentro l'app: {name or '(senza nome)'} uuid={uuid}")
    print(f"Il profilo dentro l'app contiene NFC TAG: {'sì' if tagged else 'no'} formati={formats}")
    expected = expected_profile_uuid()
    if expected and uuid != expected:
        print(f"Il profilo dentro l'app non è quello scelto ({expected}).")
        return False
    return tagged


def rezip(source, destination):
    destination = Path(destination).resolve()
    entries = [path.name for path in Path(source).iterdir()]
    if "Payload" not in entries:
        fail("L'IPA non contiene Payload. Pubblicazione interrotta.")
    fresh = destination.with_name(destination.stem + "-tagged.ipa")
    if fresh.exists():
        fresh.unlink()
    subprocess.check_call(["zip", "-qry", str(fresh), *entries], cwd=source)
    os.replace(fresh, destination)


def ipa_apps(root):
    payload = Path(root) / "Payload"
    if not payload.is_dir():
        fail("L'IPA non contiene Payload. Pubblicazione interrotta.")
    apps = [path for path in payload.glob("*.app") if path.is_dir()]
    if len(apps) != 1:
        fail("L'IPA non contiene un'app. Pubblicazione interrotta.")
    return apps[0]


def unzip_ipa(ipa):
    tmp = Path(tempfile.mkdtemp(prefix="refurbx-ipa-"))
    subprocess.check_call(["unzip", "-q", str(ipa), "-d", str(tmp)])
    return tmp, ipa_apps(tmp)


def read_identity():
    identity = Path("/tmp/refurbx-sign-identity.txt").read_text().strip()
    profile_path = Path("/tmp/refurbx-profile-path.txt").read_text().strip()
    if not identity or not profile_path:
        fail("Manca il certificato o il profilo scelti prima dell'archivio. Pubblicazione interrotta.")
    profile = load_profile(profile_path)
    if not contains_tag(profile.get("Entitlements", {})):
        fail(MISSING_TAG)
    return identity, profile_path, profile


def ensure_ipa(ipa):
    identity, profile_path, profile = read_identity()
    tmp, app = unzip_ipa(ipa)
    if not app_is_tagged(app):
        print(
            "L'export non ha lasciato TAG nella firma dell'IPA. "
            "Rifirmo con lo stesso certificato di distribuzione, il profilo che contiene TAG "
            "e RefurbX.entitlements."
        )
        resign(app, identity, profile_path, profile)
        if not app_is_tagged(app):
            fail(MISSING_TAG)
        rezip(tmp, ipa)
    verify_ipa_file(ipa)


def verify_ipa_file(ipa):
    _tmp, app = unzip_ipa(ipa)
    print(f"Controllo l'app dentro l'IPA: {ipa}")
    if not app_is_tagged(app):
        fail(MISSING_TAG)
    print("L'app dentro l'IPA ha NFC TAG nella firma che iOS legge e nel profilo.")


def repair_signed():
    root = project_root()
    ipas = sorted((root / "build/ios/ipa").glob("*.ipa"))
    if not ipas:
        fail("IPA non trovato. Pubblicazione interrotta.")
    for ipa in ipas:
        ensure_ipa(ipa)


def iter_json_documents(text):
    decoder = json.JSONDecoder()
    index = 0
    length = len(text)
    while index < length:
        while index < length and text[index] not in "{[":
            index += 1
        if index >= length:
            return
        try:
            value, end = decoder.raw_decode(text, index)
        except json.JSONDecodeError:
            index += 1
            continue
        yield value
        index = end


def walk_nodes(node, parent=None):
    if isinstance(node, dict):
        yield node, parent
        for child in node.values():
            yield from walk_nodes(child, parent=node)
    elif isinstance(node, list):
        for child in node:
            yield from walk_nodes(child, parent=parent)


def print_bundle_resource_id(path):
    text = Path(path).read_text(errors="ignore") if Path(path).exists() else ""
    for document in iter_json_documents(text):
        for node, parent in walk_nodes(document):
            if node.get("identifier") != BUNDLE:
                continue
            for candidate in (parent, node):
                resource_id = candidate.get("id") if isinstance(candidate, dict) else None
                if isinstance(resource_id, str) and resource_id:
                    print(resource_id)
                    return
    fail("App ID eu.refurbx.diagnostics non trovato nella risposta App Store Connect. Controlla integrazione, team e App ID; firma interrotta.")


def profile_blobs(text):
    seen = set()
    for document in iter_json_documents(text):
        for node, parent in walk_nodes(document):
            content = node.get("profileContent")
            if not isinstance(content, str) or len(content) < 80:
                continue
            resource_id = ""
            for candidate in (parent, node):
                if isinstance(candidate, dict) and isinstance(candidate.get("id"), str):
                    resource_id = candidate["id"]
                    break
            if not resource_id or resource_id in seen:
                continue
            seen.add(resource_id)
            name = ""
            for candidate in (node, parent):
                if isinstance(candidate, dict) and isinstance(candidate.get("name"), str):
                    name = candidate["name"]
                    break
            yield resource_id, name, content


def plist_from_profile_bytes(blob):
    text = blob.decode("iso-8859-1", errors="ignore")
    start = text.find("<?xml")
    end = text.find("</plist>")
    if start < 0 or end < 0:
        return None
    xml = text[start : end + len("</plist>")]
    try:
        parsed = plistlib.loads(xml.encode("utf-8"))
    except Exception:
        return None
    if isinstance(parsed, dict):
        return parsed
    return None


def profile_content_has_tag(content):
    try:
        blob = base64.b64decode(content)
    except Exception:
        return False, ""
    parsed = plist_from_profile_bytes(blob)
    if not parsed:
        return False, ""
    entitlements = parsed.get("Entitlements") or {}
    app_id = str(entitlements.get("application-identifier", ""))
    if BUNDLE not in app_id:
        return None, str(parsed.get("Name") or "")
    return contains_tag(entitlements), str(parsed.get("Name") or "")


def print_profiles_to_delete(path):
    text = Path(path).read_text(errors="ignore") if Path(path).exists() else ""
    found = list(profile_blobs(text))
    if not found:
        print(
            "Nessun profilo App Store decodificabile: elimino il profilo del 5 ottobre.",
            file=sys.stderr,
        )
        for resource_id in STALE_PROFILE_IDS:
            print(resource_id)
        return
    for resource_id, name, content in found:
        tagged, profile_name = profile_content_has_tag(content)
        label = profile_name or name or resource_id
        if tagged is None:
            print(f"Profilo di un'altra app, lo lascio: {label} id={resource_id}", file=sys.stderr)
            continue
        if tagged:
            print(f"Profilo con NFC TAG, lo tengo: {label} id={resource_id}", file=sys.stderr)
            continue
        print(f"Profilo senza NFC TAG, lo elimino: {label} id={resource_id}", file=sys.stderr)
        print(resource_id)


def main(argv):
    if len(argv) > 1 and argv[1] == "--repair-signed":
        repair_signed()
        return
    if len(argv) > 2 and argv[1] == "--check-ipa":
        verify_ipa_file(Path(argv[2]))
        return
    if len(argv) > 2 and argv[1] == "--bundle-resource-id":
        print_bundle_resource_id(argv[2])
        return
    if len(argv) > 2 and argv[1] == "--drop-untagged":
        print_profiles_to_delete(argv[2])
        return
    prepare()


if __name__ == "__main__":
    main(sys.argv)
