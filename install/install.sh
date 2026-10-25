#!/bin/bash
# The first install of Real Agent on a Mac, in one command. It is in Real Agent's public marketplace, beside
# install.ps1 for Windows.
#
#   bash install.sh <marketplace> --owner [--folder <folder>]
#   bash install.sh <marketplace> --email <email> [okb setup's other options]
#
# <marketplace> is Real Agent's public marketplace, as `claude plugin marketplace add` takes it: a GitHub
# owner/repo, a git or https address, or a folder. Real Agent gives it with this script.
#
# It installs Homebrew, then each program the okb plugin uses that is missing, with Homebrew, and Node.js 26 with
# nodejs.org's installer. It prints one line for each: installed, already there, or failed with the command to run
# by hand. It then adds the marketplace, installs the okb, real-agent and business-analyst plugins from it, and runs
# the okb plugin's `okb.mjs setup` with the options given. okb setup makes the person's folder, ~/real-agent unless
# --folder names another, signs in as --email, and runs okb sync, which installs the firm's own release of its
# plugins in place of the public copy.
#
# --owner is the firm's owner's first run, before the firm has a Supabase project. okb setup --owner makes the folder
# and names the business analyst, business-analyst:business-analyst, as its agent, and neither signs in nor runs
# okb sync. It ends: "Start a new Code session on <folder>, and type: Set up Real Agent".
#
# This script never asks for or keeps a password. okb setup's sign-in asks for the person's password at its own
# prompt. Homebrew and Node.js's installer ask for the Mac's own password, with sudo, only when they install.
# A folder already signed in keeps its password: --new-password is left out for it.
# Run it again to carry on from where it stopped: each step already done says so.
# Each program's own output goes to the log, a new file for each run, $TMPDIR/okb-install-log.XXXXXX, that only this
# user can read. Homebrew's and Node.js's installers are downloaded into a new folder that only this user can open,
# checked again just before they run, and removed when the script ends.
set -u

USAGE="Usage: bash install.sh <marketplace> --owner [--folder <folder>]
       bash install.sh <marketplace> --email <email> [--folder <folder>] [--url <project URL> --key <publishable key>] [--agent <plugin>:<agent>] [--new-password]"
if [ "$(uname -s)" != "Darwin" ]; then echo "install.sh is for macOS. On Windows, run install.ps1."; exit 2; fi
MARKETPLACE="${1:-}"
case "$MARKETPLACE" in ""|-*) echo "$USAGE"; exit 2 ;; esac
shift

# okb setup's options, with the folder it sets up. --email, or --owner with no other option, is checked here, before
# any install.
args=() folder="" email="" owner=0
while [ $# -gt 0 ]; do
  case "$1" in
    --folder) folder="${2:-}"; shift 2 || { echo "$USAGE"; exit 2; } ;;
    --email) email="${2:-}"; args+=("$1" "$email"); shift 2 || { echo "$USAGE"; exit 2; } ;;
    --owner) owner=1; args+=("$1"); shift ;;
    *) args+=("$1"); shift ;;
  esac
done
if [ "$owner" = 1 ]; then
  if [ "${#args[@]}" != 1 ]; then echo "--owner takes only --folder: the firm has no project to sign in to yet."; echo "$USAGE"; exit 2; fi
else
  case "$email" in ?*@?*) ;; *) echo "--email is needed: the work email your administrator gave you."; echo "The firm's owner, before the firm has a project, gives --owner instead."; echo "$USAGE"; exit 2 ;; esac
fi
case "$folder" in ""|-*) folder="$HOME/real-agent" ;; esac
case "$folder" in "~/"*) folder="$HOME/${folder#\~/}" ;; esac

# The name of Real Agent's marketplace in Claude Code, which each plugin's id ends with.
MARKETPLACE_NAME="real-agent"
PLUGINS="okb real-agent business-analyst"

# Each download, pinned, with its SHA-256. A test checks Node.js's line against the okb plugin's project.json.
HOMEBREW_URL="https://raw.githubusercontent.com/Homebrew/install/be041513824fd2666a0e93cf5c3b0ca3bb0eb4b6/install.sh"
HOMEBREW_SHA256="5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148"
NODE_URL="https://nodejs.org/dist/v26.12.0/node-v26.12.0.pkg"
NODE_SHA256="4a52bdf4a236145267143ce2cc8c058def3485a5901af055572d5f15d026cf77"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin"
MODEL_SHA256="60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"

# whisper.cpp's model: Homebrew's copy, which the okb plugin finds itself, or else this script's own copy.
OWN_MODEL="$HOME/.local/share/okb/whisper/ggml-base.bin"
TEMP_DIR="${TMPDIR:-/tmp}"; TEMP_DIR="${TEMP_DIR%/}"
export HOMEBREW_NO_ENV_HINTS=1
STAGE=""
cleanup() { [ -z "$STAGE" ] || rm -rf "$STAGE"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
LOG="$(umask 077 && mktemp "$TEMP_DIR/okb-install-log.XXXXXX")" || { echo "install.sh could not make its log in $TEMP_DIR."; exit 1; }
STAGE="$(umask 077 && mktemp -d "$TEMP_DIR/okb-install-stage.XXXXXX")" || { echo "install.sh could not make its download folder in $TEMP_DIR."; exit 1; }
chmod 700 "$STAGE"

failed=""
say() { echo "$1: $2"; }
sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

# A plain file, not a link, with the checksum.
verified() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(sha256 "$1")" = "$2" ]; }

# Downloads url, to be run, into a new folder inside the private download folder, under name, and prints its path.
# Nothing there before is used. Removes a download that fails its checksum.
stage() {
  local d; d="$(mktemp -d "$STAGE/download.XXXXXX")" || return 1
  if curl -fsSL --retry 3 -o "$d/$2" "$1" >>"$LOG" 2>&1 && verified "$d/$2" "$3"; then echo "$d/$2"; return 0; fi
  echo "$1 did not download, or does not match its checksum." >>"$LOG"
  rm -rf "$d"
  return 1
}

# Downloads url to file, unless file is already there with the checksum. Removes a file that fails it. Only for a file
# that is read, never run: whisper.cpp's model.
fetch() {
  [ -f "$2" ] && [ "$(sha256 "$2")" = "$3" ] && return 0
  mkdir -p "$(dirname "$2")"
  curl -fsSL --retry 3 -o "$2.part" "$1" >>"$LOG" 2>&1 || { rm -f "$2.part"; return 1; }
  if [ "$(sha256 "$2.part")" != "$3" ]; then
    echo "$1 does not match its checksum." >>"$LOG"
    rm -f "$2.part"
    return 1
  fi
  mv "$2.part" "$2"
}

# One step: label, the test that it is done, the install, and the command a person runs by hand.
program() {
  if "$2"; then say "$1" "already there"; return 0; fi
  if "$3" >>"$LOG" 2>&1 && hash -r && "$2"; then say "$1" "installed"; return 0; fi
  say "$1" "failed. Run it by hand: $4"
  failed="$failed|$1"
  return 1
}

# The Command Line Tools give /usr/bin/git and /usr/bin/python3. Without them, each opens a dialog instead.
tools() { xcode-select -p >/dev/null 2>&1; }
real() { local p; p="$(command -v "$1")" || return 1; [ "$p" != "/usr/bin/$1" ] || tools; }

brew_path() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && { echo "$b"; return 0; }; done
  command -v brew
}
have_brew() { local b; b="$(brew_path)" || return 1; eval "$("$b" shellenv)"; }
install_brew() {
  sudo -v -p "Your Mac password, to install Homebrew: " || return 1
  local f; f="$(stage "$HOMEBREW_URL" install.sh "$HOMEBREW_SHA256")" || return 1
  verified "$f" "$HOMEBREW_SHA256" || { echo "Homebrew's installer changed after its check, and was not run."; return 1; }
  NONINTERACTIVE=1 /bin/bash "$f"
}

have_claude() { command -v claude >/dev/null; }
install_claude() { brew install --cask claude-code; }

node26() { local n; for n in "$(command -v node)" /usr/local/bin/node; do [ -x "$n" ] && [ "$("$n" -v 2>/dev/null | cut -d. -f1)" = "v26" ] && { echo "$n"; return 0; }; done; return 1; }
path_node26() { [ "$(node -v 2>/dev/null | cut -d. -f1)" = "v26" ]; }
# Node.js 26 is there when a v26 node is on the PATH or where nodejs.org's installer puts it. A version manager's own
# node may come first on the PATH, and okb setup runs with the v26 node found.
have_node() { node26 >/dev/null; }
install_node() {
  local f
  if ! node26 >/dev/null; then
    f="$(stage "$NODE_URL" node-v26.12.0.pkg "$NODE_SHA256")" || return 1
    sudo -v -p "Your Mac password, to install Node.js 26: " || return 1
    verified "$f" "$NODE_SHA256" || { echo "The Node.js installer changed after its check, and was not run."; return 1; }
    sudo installer -pkg "$f" -target / || return 1
  fi
  # Homebrew's own node, in front of nodejs.org's on the PATH, is set aside.
  hash -r
  if ! path_node26; then for f in $(brew list --formula 2>/dev/null | grep -E '^node(@[0-9]+)?$'); do brew unlink "$f"; done; fi
}

have_git() { real git && git --version >/dev/null 2>&1; }
install_git() { brew install git; }
have_python() { real python3 && python3 -c "import sys; sys.exit(sys.version_info[0] != 3)" 2>/dev/null; }
install_python() { brew install python; }
have_chrome() { [ -d "/Applications/Google Chrome.app" ] || [ -d "/Applications/Chromium.app" ] || [ -d "$HOME/Applications/Google Chrome.app" ]; }
install_chrome() { brew install --cask google-chrome; }
have_poppler() { command -v pdftoppm >/dev/null; }
install_poppler() { brew install poppler; }
have_tesseract() { command -v tesseract >/dev/null; }
install_tesseract() { brew install tesseract; }
have_ffmpeg() { command -v ffmpeg >/dev/null; }
install_ffmpeg() { brew install ffmpeg; }
have_magick() { command -v magick >/dev/null; }
install_magick() { brew install imagemagick; }
have_whisper() { command -v whisper-cli >/dev/null; }
install_whisper() { brew install whisper-cpp; }
# The model the okb plugin uses: Homebrew's, where the plugin looks, or this script's own copy.
model() {
  local m
  for m in "$(brew --prefix 2>/dev/null)/share/whisper-cpp/ggml-base.bin" "$OWN_MODEL"; do
    [ -f "$m" ] && [ "$(sha256 "$m")" = "$MODEL_SHA256" ] && { echo "$m"; return 0; }
  done
  return 1
}
have_model() { model >/dev/null; }
install_model() { fetch "$MODEL_URL" "$OWN_MODEL" "$MODEL_SHA256"; }

if ! program "Homebrew" have_brew install_brew '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'; then
  echo "Each other program is installed with Homebrew. Install it, then run this again. The log is $LOG."
  exit 1
fi
program "Claude Code's command-line tool" have_claude install_claude "brew install --cask claude-code"
program "Node.js 26" have_node install_node "cd \"\$(mktemp -d)\" && curl -fsSLO $NODE_URL && sudo installer -pkg node-v26.12.0.pkg -target /"
program "Git" have_git install_git "brew install git"
program "Python 3" have_python install_python "brew install python"
program "Google Chrome" have_chrome install_chrome "brew install --cask google-chrome"
program "Poppler" have_poppler install_poppler "brew install poppler"
program "Tesseract" have_tesseract install_tesseract "brew install tesseract"
program "FFmpeg" have_ffmpeg install_ffmpeg "brew install ffmpeg"
program "ImageMagick" have_magick install_magick "brew install imagemagick"
program "whisper.cpp" have_whisper install_whisper "brew install whisper-cpp"
program "whisper.cpp's model" have_model install_model "mkdir -p \"$(dirname "$OWN_MODEL")\" && curl -fL -o \"$OWN_MODEL\" $MODEL_URL"

case "$failed" in *"|Claude Code's command-line tool"*|*"|Node.js 26"*|*"|Git"*)
  echo "The first install needs Claude Code's command-line tool, Node.js 26 and Git. Install each that failed, then run this again. The log is $LOG."
  exit 1 ;;
esac
[ -z "$failed" ] || echo "Install each program that failed with its command, later. The log is $LOG."
NODE="$(node26)"

# The marketplace's folder on this computer, from Claude Code's list of marketplaces, or nothing.
marketplace_folder() {
  claude plugin marketplace list --json 2>>"$LOG" | "$NODE" -e '
    let t = ""; process.stdin.on("data", c => t += c).on("end", () => {
      try { const m = JSON.parse(t).find(m => m.name === process.argv[1]); if (m?.installLocation) console.log(m.installLocation); } catch {}
    });' "$MARKETPLACE_NAME"
}
have_marketplace() { [ -n "$(marketplace_folder)" ]; }
add_marketplace() { claude plugin marketplace add "$MARKETPLACE"; }
if ! program "Real Agent's marketplace" have_marketplace add_marketplace "claude plugin marketplace add $MARKETPLACE"; then
  echo "The plugins come from Real Agent's marketplace. Check its address with Real Agent, then run this again. The log is $LOG."
  exit 1
fi

# Each plugin installed from the marketplace. Where the okb plugin cannot find whisper.cpp's model itself, its settings
# name this script's copy.
installed() {
  claude plugin list --json 2>>"$LOG" | "$NODE" -e '
    let t = ""; process.stdin.on("data", c => t += c).on("end", () => {
      try { process.exit(JSON.parse(t).some(p => p.id === process.argv[1]) ? 0 : 1); } catch { process.exit(1); }
    });' "$1@$MARKETPLACE_NAME"
}
config=()
if have_whisper && [ "$(model)" = "$OWN_MODEL" ]; then
  config=(--config "whisper_cli=$(command -v whisper-cli)" --config "whisper_model=$OWN_MODEL")
  claude plugin install "okb@$MARKETPLACE_NAME" "${config[@]}" >>"$LOG" 2>&1
fi
for plugin in $PLUGINS; do
  eval "have_$plugin() { installed $plugin; }; install_$plugin() { claude plugin install $plugin@$MARKETPLACE_NAME; }"
  program "The $plugin plugin" "have_$plugin" "install_$plugin" "claude plugin install $plugin@$MARKETPLACE_NAME"
done
case "$failed" in *"|The "*" plugin"*)
  echo "Install each plugin that failed with its command, then run this again. The log is $LOG."
  exit 1 ;;
esac

OKB="$(marketplace_folder)/plugins/okb/cli/okb.mjs"
if [ ! -f "$OKB" ]; then
  echo "Real Agent's marketplace holds no okb.mjs at $OKB. Check its address with Real Agent. The log is $LOG."
  exit 1
fi

# A folder already signed in keeps its password.
setup=()
for a in ${args[@]+"${args[@]}"}; do
  if [ "$a" = "--new-password" ] && [ -f "$folder/.okb-actor.json" ]; then
    echo "$folder is already signed in, so your password stays as it is."
  else
    setup+=("$a")
  fi
done
echo "Setting up your folder with okb setup."
# exec ends this shell without its exit trap, so the download folder goes first.
cleanup; STAGE=""; trap - EXIT
exec "$NODE" "$OKB" setup --folder "$folder" ${setup[@]+"${setup[@]}"}
