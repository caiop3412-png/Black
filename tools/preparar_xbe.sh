#!/data/data/com.termux/files/usr/bin/bash
# Termux (ou Linux): tira o default.xbe da sua ISO do Xbox e criptografa em ci/default.xbe.enc.
# Uso: bash tools/preparar_xbe.sh caminho/da/black.iso
# Pede a senha duas vezes. A mesma senha vai no segredo XBE_KEY do GitHub (Settings > Secrets > Actions).
# Precisa de: python e openssl (pkg install python openssl-tool).
set -e
ISO="$1"
[ -f "$ISO" ] || { echo "uso: bash tools/preparar_xbe.sh black.iso"; exit 1; }
cd "$(dirname "$0")/.."
mkdir -p assets ci
python -I tools/xdvdfs.py "$ISO" default.xbe assets/default.xbe
echo "SHA1 do xbe:"; sha1sum assets/default.xbe
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -in assets/default.xbe -out ci/default.xbe.enc
rm -f assets/default.xbe
echo "pronto: ci/default.xbe.enc (faz commit dele; NUNCA do assets/ nem da ISO)"
