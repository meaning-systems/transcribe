#!/bin/bash
# transcribe - Local audio transcription using Parakeet v3 CoreML
#
# Powered by FluidAudio (https://github.com/FluidInference/FluidAudio)
# Model: NVIDIA Parakeet TDT 0.6B via CoreML on Apple Silicon
#
# Usage:
#   transcribe <audio-file> [output-dir]       — single file
#   transcribe <directory> [output-dir]        — bulk transcribe
#   transcribe setup                           — first-time setup
#   transcribe models                          — list models
#   transcribe install <v2|v3>                 — download a model
#
# Options:
#   --model <v2|v3>                            — model version (default: v3)

set -euo pipefail

# --- Configuration ---
TOOLS_DIR="$HOME/.claude/bin/parakeet"
BINARY="$TOOLS_DIR/parakeet-transcribe"
MODELCTL="$TOOLS_DIR/parakeet-modelctl"
MODEL_BASE="$HOME/Library/Application Support/FluidAudio/Models"
BUILD_DIR="$HOME/.claude/cache/parakeet-build"

# --- Helpers ---
die() { echo "Error: $*" >&2; exit 1; }
info() { echo "$*" >&2; }

resolve_path() {
    realpath "$1" 2>/dev/null || {
        if [[ "$1" = /* ]]; then echo "$1"; else echo "$PWD/$1"; fi
    }
}

# --- Setup: generates and builds minimal Swift tools from FluidAudio ---
do_setup() {
    [[ "$(uname)" == "Darwin" ]] || die "Requires macOS"
    command -v swift >/dev/null 2>&1 || die "Swift not found. Install: xcode-select --install"

    info "Setting up Parakeet transcription tools..."
    info ""
    info "This will:"
    info "  1. Generate a minimal Swift package (~FluidAudio dependency)"
    info "  2. Build two binaries (transcribe + model manager)"
    info "  3. Download Parakeet v3 model from HuggingFace"
    info ""

    mkdir -p "$BUILD_DIR/Sources/parakeet-transcribe"
    mkdir -p "$BUILD_DIR/Sources/parakeet-modelctl"

    # --- Package.swift ---
    cat > "$BUILD_DIR/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "parakeet-tools",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9")
    ],
    targets: [
        .executableTarget(
            name: "parakeet-transcribe",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .executableTarget(
            name: "parakeet-modelctl",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        )
    ]
)
EOF

    # --- Transcription binary ---
    cat > "$BUILD_DIR/Sources/parakeet-transcribe/main.swift" <<'EOF'
import FluidAudio
import Foundation

@main struct ParakeetTranscribe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 1 else {
            fputs("Usage: parakeet-transcribe <audio-file> [--version v2|v3] [--format txt|json|both] [--output-dir <dir>]\n", stderr)
            Foundation.exit(1)
        }

        var files: [URL] = []
        var version: AsrModelVersion = .v3
        var outputDir: URL? = nil
        var outputFormat = "txt"
        var overwrite = false
        var inputDir: URL? = nil

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--version":
                i += 1; guard i < args.count else { fputs("Missing --version value\n", stderr); Foundation.exit(1) }
                version = args[i] == "v2" ? .v2 : .v3
            case "--output-dir":
                i += 1; guard i < args.count else { fputs("Missing --output-dir value\n", stderr); Foundation.exit(1) }
                outputDir = URL(fileURLWithPath: (args[i] as NSString).expandingTildeInPath, isDirectory: true)
            case "--format":
                i += 1; guard i < args.count else { fputs("Missing --format value\n", stderr); Foundation.exit(1) }
                outputFormat = args[i]
            case "--overwrite":
                overwrite = true
            case "--input-dir":
                i += 1; guard i < args.count else { fputs("Missing --input-dir value\n", stderr); Foundation.exit(1) }
                inputDir = URL(fileURLWithPath: (args[i] as NSString).expandingTildeInPath, isDirectory: true)
            default:
                files.append(URL(fileURLWithPath: (args[i] as NSString).expandingTildeInPath))
            }
            i += 1
        }

        // Directory mode: enumerate audio files
        if let dir = inputDir {
            let exts: Set<String> = ["wav","mp3","m4a","aac","flac","ogg","opus","aiff","aif","caf","mp4","mov","webm"]
            let fm = FileManager.default
            if let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator {
                    if let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                       vals.isRegularFile == true,
                       exts.contains(url.pathExtension.lowercased()) {
                        files.append(url)
                    }
                }
            }
            files.sort { $0.path < $1.path }
        }

        guard !files.isEmpty else {
            fputs("No audio files found\n", stderr); Foundation.exit(1)
        }

        do {
            let modelDir = AsrModels.defaultCacheDirectory(for: version)

            // Auto-download model if not present
            if !AsrModels.modelsExist(at: modelDir, version: version) {
                fputs("Model not found locally. Downloading from HuggingFace...\n", stderr)
                _ = try await AsrModels.download(to: modelDir, version: version)
                fputs("Model downloaded.\n", stderr)
            }

            let models = try await AsrModels.load(from: modelDir, version: version)
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)

            let total = files.count
            let writesTxt = outputFormat == "txt" || outputFormat == "both"
            let writesJson = outputFormat == "json" || outputFormat == "both"

            for (index, file) in files.enumerated() {
                let basename = file.lastPathComponent
                let relative: String
                if let dir = inputDir {
                    let prefix = dir.standardizedFileURL.path.hasSuffix("/") ? dir.standardizedFileURL.path : dir.standardizedFileURL.path + "/"
                    relative = file.standardizedFileURL.path.hasPrefix(prefix) ? String(file.standardizedFileURL.path.dropFirst(prefix.count)) : basename
                } else {
                    relative = basename
                }

                // Emit NDJSON events for progress
                emit("file_started", ["index": index + 1, "total": total, "file": file.path, "relative": relative])

                do {
                    let result = try await manager.transcribe(file)

                    if let outDir = outputDir {
                        let fm = FileManager.default
                        if writesTxt {
                            let txtPath = outDir.appendingPathComponent(relative + ".txt")
                            try fm.createDirectory(at: txtPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try result.text.write(to: txtPath, atomically: true, encoding: .utf8)
                        }
                        if writesJson {
                            let jsonPath = outDir.appendingPathComponent(relative + ".json")
                            try fm.createDirectory(at: jsonPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                            let payload: [String: Any] = [
                                "text": result.text,
                                "confidence": result.confidence,
                                "duration_seconds": result.duration,
                                "processing_seconds": result.processingTime,
                                "rtfx": result.rtfx
                            ]
                            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                            try data.write(to: jsonPath)
                        }
                    }

                    emit("file_done", [
                        "index": index + 1, "total": total,
                        "file": file.path, "relative": relative,
                        "confidence": result.confidence,
                        "duration_seconds": result.duration,
                        "processing_seconds": result.processingTime,
                        "rtfx": result.rtfx
                    ])

                    // If no output dir, print text to stdout
                    if outputDir == nil {
                        print(result.text)
                    }
                } catch {
                    emit("file_failed", ["index": index + 1, "total": total, "file": file.path, "relative": relative, "error": String(describing: error)])
                }
            }

            emit("summary", ["total": total, "processed": files.count])
            manager.cleanup()
        } catch {
            fputs("Fatal: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    static func emit(_ event: String, _ fields: [String: Any]) {
        var payload = fields
        payload["event"] = event
        payload["timestamp"] = ISO8601DateFormatter.string(from: Date(), timeZone: .init(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
EOF

    # --- Model manager binary ---
    cat > "$BUILD_DIR/Sources/parakeet-modelctl/main.swift" <<'EOF'
import FluidAudio
import Foundation

@main struct ParakeetModelCtl {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            print("Usage: parakeet-modelctl <list|install|resolve> [--model v2|v3]")
            Foundation.exit(1)
        }

        func parseModel() -> AsrModelVersion {
            if let idx = args.firstIndex(of: "--model"), idx + 1 < args.count {
                return args[idx + 1] == "v2" ? .v2 : .v3
            }
            return .v3
        }

        func modelId(_ v: AsrModelVersion) -> String {
            v == .v3 ? "parakeet-tdt-0.6b-v3-coreml" : "parakeet-tdt-0.6b-v2-coreml"
        }

        do {
            switch command {
            case "list":
                for v: AsrModelVersion in [.v3, .v2] {
                    let dir = AsrModels.defaultCacheDirectory(for: v)
                    let installed = AsrModels.modelsExist(at: dir, version: v)
                    let label = v == .v3 ? "v3" : "v2"
                    let status = installed ? "installed" : "not installed"
                    let desc = v == .v3 ? "25 European languages" : "English-focused"
                    print("  \(label)  \(modelId(v))  \(status)  \(desc)")
                    if installed { print("       path: \(dir.path)") }
                }
            case "install":
                let v = parseModel()
                let dir = AsrModels.defaultCacheDirectory(for: v)
                if AsrModels.modelsExist(at: dir, version: v) {
                    print("Already installed: \(dir.path)")
                } else {
                    fputs("Downloading \(modelId(v)) from HuggingFace...\n", stderr)
                    _ = try await AsrModels.download(to: dir, version: v)
                    print("Installed to: \(dir.path)")
                }
            case "resolve":
                let v = parseModel()
                let dir = AsrModels.defaultCacheDirectory(for: v)
                let installed = AsrModels.modelsExist(at: dir, version: v)
                print("\(modelId(v)): \(installed ? "installed" : "not installed") at \(dir.path)")
            default:
                fputs("Unknown command: \(command)\n", stderr)
                Foundation.exit(1)
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
EOF

    info "Building (release mode)... first build takes ~3-5 minutes for dependency resolution."
    if ! (cd "$BUILD_DIR" && swift build -c release 2>&1 | tail -10); then
        die "Build failed. Check Swift/Xcode installation."
    fi

    mkdir -p "$TOOLS_DIR"
    cp "$BUILD_DIR/.build/release/parakeet-transcribe" "$TOOLS_DIR/"
    cp "$BUILD_DIR/.build/release/parakeet-modelctl" "$TOOLS_DIR/"
    chmod +x "$TOOLS_DIR/parakeet-transcribe" "$TOOLS_DIR/parakeet-modelctl"

    info ""
    info "Binaries installed to $TOOLS_DIR"

    # Auto-download v3 model
    local v3_dir="$MODEL_BASE/parakeet-tdt-0.6b-v3-coreml"
    if [[ -d "$v3_dir" ]]; then
        info "Model v3 already installed."
    else
        info "Downloading Parakeet v3 model..."
        "$MODELCTL" install --model v3
    fi

    info ""
    info "Setup complete! Run: transcribe <audio-file>"
}

# --- Models command ---
do_models() {
    if [[ -x "$MODELCTL" ]]; then
        "$MODELCTL" list
    else
        info "Available models (run 'transcribe setup' to install):"
        info "  v3  parakeet-tdt-0.6b-v3-coreml  25 European languages (recommended)"
        info "  v2  parakeet-tdt-0.6b-v2-coreml  English-focused, smaller"
    fi
}

# --- Install command ---
do_install() {
    local version="${1:-}"
    [[ -n "$version" ]] || die "Usage: transcribe install <v2|v3>"
    [[ "$version" == "v2" || "$version" == "v3" ]] || die "Invalid model: $version. Use v2 or v3"
    ensure_binary
    "$MODELCTL" install --model "$version"
}

# --- Find binary ---
ensure_binary() {
    if [[ -x "$BINARY" ]]; then return 0; fi
    die "Not installed. Run: transcribe setup"
}

ensure_model() {
    local version="$1"
    local model_dir="$MODEL_BASE/parakeet-tdt-0.6b-${version}-coreml"
    [[ -d "$model_dir" ]] || die "Model $version not installed. Run: transcribe install $version"
}

# --- Parse flags ---
MODEL_VERSION="v3"
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) MODEL_VERSION="${2:-}"; shift 2 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done
set -- "${ARGS[@]}"

# --- Route commands ---
case "${1:-}" in
    setup)   do_setup; exit 0 ;;
    models)  do_models; exit 0 ;;
    install) do_install "${2:-}"; exit 0 ;;
    --help|-h|help|"")
        cat >&2 <<'USAGE'
transcribe - Local audio transcription using Parakeet CoreML

Powered by FluidAudio (github.com/FluidInference/FluidAudio)
Model: NVIDIA Parakeet TDT 0.6B | 25 European languages

Usage:
  transcribe <audio-file> [output-dir]    Transcribe a single file
  transcribe <directory> [output-dir]     Transcribe all audio in a directory
  transcribe setup                        First-time setup (~5 min)
  transcribe models                       List available models
  transcribe install <v2|v3>              Download a model

Options:
  --model <v2|v3>   Model version (default: v3)

Supported: wav, mp3, m4a, aac, flac, ogg, opus, aiff, caf, mp4, mov, webm

First time? Run: transcribe setup
USAGE
        exit 0 ;;
esac

# --- Transcribe ---
ensure_binary
ensure_model "$MODEL_VERSION"

INPUT="$(resolve_path "$1")"
[[ -e "$INPUT" ]] || die "Not found: $INPUT"

# --- Directory mode ---
if [[ -d "$INPUT" ]]; then
    OUTPUT_DIR="${2:+$(resolve_path "$2")}"
    OUTPUT_DIR="${OUTPUT_DIR:-$INPUT}"
    [[ -n "${2:-}" ]] && mkdir -p "$OUTPUT_DIR"

    info "Transcribing: $INPUT"
    info "Output: $OUTPUT_DIR"
    info "Model: parakeet-tdt-0.6b-${MODEL_VERSION}"
    info ""

    "$BINARY" \
        --input-dir "$INPUT" \
        --output-dir "$OUTPUT_DIR" \
        --version "$MODEL_VERSION" \
        --format both \
        --overwrite \
        2>&1 | while IFS= read -r line; do
            event=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('event',''))" 2>/dev/null || echo "")
            case "$event" in
                file_started)
                    file=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('relative',''))" 2>/dev/null)
                    info "  > $file" ;;
                file_done)
                    conf=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(f'{d.get(\"confidence\",0):.1%}')" 2>/dev/null)
                    info "    done ($conf)" ;;
                file_failed)
                    err=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('error','unknown'))" 2>/dev/null)
                    info "    FAILED: $err" ;;
                summary)
                    stats=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(f'{d[\"processed\"]} done ({d.get(\"duration_seconds\",0):.1f}s)')" 2>/dev/null || echo "")
                    [[ -n "$stats" ]] && { info ""; info "Summary: $stats"; } ;;
            esac
        done

    info ""
    info "Transcripts:"
    find "$OUTPUT_DIR" -name "*.txt" -not -path "*/_reports/*" -not -path "*/_archive/*" | sort | while read -r f; do
        info "  $f"
    done
    exit 0
fi

# --- Single file mode ---
BASENAME="$(basename "$INPUT")"
[[ -f "$INPUT" ]] || die "File not found: $INPUT"

if [[ $# -ge 2 ]]; then
    OUTPUT_DIR="$(resolve_path "$2")"
    mkdir -p "$OUTPUT_DIR"
    "$BINARY" "$INPUT" --output-dir "$OUTPUT_DIR" --version "$MODEL_VERSION" --format both >/dev/null
    info "Saved to: $OUTPUT_DIR/$BASENAME.txt"
else
    # Print to stdout
    "$BINARY" "$INPUT" --version "$MODEL_VERSION" 2>/dev/null
fi
