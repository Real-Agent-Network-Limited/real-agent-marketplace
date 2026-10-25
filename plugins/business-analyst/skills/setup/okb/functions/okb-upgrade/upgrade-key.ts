// Real Agent's upgrade public key: the Ed25519 key, raw and in base64, whose private half signs each upgrade with
// scripts/sign-upgrade.mjs. okb-upgrade applies only an upgrade this key verifies. The private key never leaves the
// signer's computer, and is never in this repository. A new key pair, from sign-upgrade.mjs --new-key, replaces this
// line, and reaches each client when okb-upgrade is deployed again.
export const UPGRADE_PUBLIC_KEY = "fHH4KLAqJsnSKxsU0OAbe4WANaM9jTPM8ueM5G9TgLE=";
