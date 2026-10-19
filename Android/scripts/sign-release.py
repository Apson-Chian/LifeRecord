#!/usr/bin/env python3
"""Sign an aligned release APK with LifeRecord's persisted beta.4 certificate."""
import argparse
import getpass
import hashlib
import os
from pathlib import Path
import subprocess
import sys

CERTIFICATE_SHA256 = "c691f48a7ba035676bc7b7c678f151c2377bcb374e8874aa0e31c2aed4828b7a"
KEY_ALIAS = "liferecord-release"
KEYCHAIN_SERVICE = "ltd.apsonchian.liferecord.android-signing"


def run(command, *, env=None):
    result = subprocess.run(command, env=env, capture_output=True)
    if result.returncode:
        # Tool diagnostics can include configuration details; do not echo them.
        raise RuntimeError(f"{Path(str(command[0])).name} failed (exit {result.returncode})")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path, help="aligned unsigned Release APK")
    parser.add_argument("output", type=Path, help="new signed APK path; must not exist")
    parser.add_argument("--keystore", type=Path,
                        default=Path.home() / ".android/liferecord-signing/release.p12")
    parser.add_argument("--build-tools", type=Path, help="SDK build-tools directory")
    args = parser.parse_args()
    if not args.apk.is_file() or not args.keystore.is_file():
        raise RuntimeError("APK or persisted keystore missing; never generate a replacement signing key")
    if args.output.exists() or args.apk.resolve() == args.output.resolve():
        raise RuntimeError("Output must be a new file, different from the input APK")

    env = os.environ.copy()
    java_home = env.get("JAVA_HOME")
    if not java_home and sys.platform == "darwin":
        java_home = run(["/usr/libexec/java_home", "-v", "17"]).decode().strip()
        env["JAVA_HOME"] = java_home
    keytool = str(Path(java_home) / "bin/keytool") if java_home else "keytool"
    tools = args.build_tools
    if not tools:
        sdk = Path(env.get("ANDROID_SDK_ROOT") or env.get("ANDROID_HOME") or
                   Path.home() / "Library/Android/sdk")
        tools = sdk / "build-tools/35.0.0"
    signer, aligner = tools / "apksigner", tools / "zipalign"
    if not signer.is_file() or not aligner.is_file():
        raise RuntimeError("Android build-tools missing; set --build-tools or ANDROID_SDK_ROOT")

    password = env.get("LIFERECORD_SIGNING_PASSWORD")
    if not password and sys.platform == "darwin":
        result = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE,
                                 "-a", "release", "-w"], capture_output=True)
        if result.returncode == 0:
            password = result.stdout.decode().rstrip("\r\n")
    if not password:
        if not sys.stdin.isatty():
            raise RuntimeError("Signing password unavailable in Keychain or LIFERECORD_SIGNING_PASSWORD")
        password = getpass.getpass("LifeRecord keystore password: ")
    env["LIFERECORD_SIGNING_PASSWORD"] = password
    certificate = run([keytool, "-exportcert", "-alias", KEY_ALIAS,
                       "-keystore", str(args.keystore), "-storepass:env", "LIFERECORD_SIGNING_PASSWORD"], env=env)
    if hashlib.sha256(certificate).hexdigest() != CERTIFICATE_SHA256:
        raise RuntimeError("Signing certificate mismatch; refusing to break existing beta.4+ installs")
    run([str(aligner), "-c", "4", str(args.apk)], env=env)
    run([str(signer), "sign", "--ks", str(args.keystore), "--ks-key-alias", KEY_ALIAS,
         "--ks-pass", "env:LIFERECORD_SIGNING_PASSWORD", "--key-pass", "env:LIFERECORD_SIGNING_PASSWORD",
         "--out", str(args.output), str(args.apk)], env=env)
    certificate_report = run([str(signer), "verify", "--verbose", "--print-certs", str(args.output)], env=env).decode()
    if f"Signer #1 certificate SHA-256 digest: {CERTIFICATE_SHA256}" not in certificate_report:
        raise RuntimeError("Signed APK certificate verification failed; do not distribute output")
    digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
    print(f"Signed and verified: {args.output}\nCertificate SHA-256: {CERTIFICATE_SHA256}\nAPK SHA-256: {digest}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as error:
        sys.exit(str(error))
