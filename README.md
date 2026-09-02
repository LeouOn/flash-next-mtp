# Flash-Next MTP (Strix Halo / Ryzen AI Max+ 395)

Serve **Qwen3.8-Flash-Next Uncensored** with Unsloth's official MTP draft head
on llama.cpp. LM Studio cannot do this: public GGUFs drop the MTP tensors, and
stock ggml-org llama.cpp still has no qwen4exp MTP graph.

Measured on this recipe, Windows Vulkan, Q3_K_S uncensored + MTP Q8_0: **~23 tok/s**.

## What you need

| Piece | Where |
|---|---|
| Target GGUF | your uncensored file, e.g. mradermacher `…i1-Q3_K_S.gguf` (~83 GB) |
| MTP sidecar | Unsloth `MTP/mtp-Qwen3.8-Flash-Next-Q8_0.gguf` (self-contained, ~3.85 GB) |
| Engine | Unsloth llama.cpp `b10715-mix-86bd2d3` **Vulkan** (has qwen4exp MTP) |

Do **not** use the `shared-` MTP file as the only draft: llama.cpp's `--fit`
pass loads it alone, it has no `token_embd.weight`, and drafting is silently
dropped. This recipe uses `--fit off` and the self-contained Q8_0 head.

## Windows

```powershell
cd flash-next-mtp
.\setup.ps1          # engine + MTP sidecar
.\start.ps1          # listens on 127.0.0.1:8097
```

Point the client at `http://127.0.0.1:8097/v1` with header:

```
Authorization: Bearer <contents of api-key.txt>
```

`api-key.txt` is created on first start and is gitignored.

```powershell
.\start.ps1 -NMax 2
.\start.ps1 -Ctx 16384
.\start.ps1 -NoMtp
.\start.ps1 -WebUi          # local UI, still API-key gated
.\start.ps1 -ListenLan      # 0.0.0.0 — keep the key private
.\stats.ps1                 # /metrics + /slots + log grep
```

## Linux (expected faster on this APU)

Extract Unsloth `app-b10715-mix-86bd2d3-linux-x64-vulkan.tar.gz` (or
`…-rocm-gfx1151.tar.gz`) into `bin/`, put the same GGUFs on disk:

```bash
export FLASH_NEXT_MODEL=/path/to/Qwen3.8-Flash-Next-Uncensored.i1-Q3_K_S.gguf
chmod +x start.sh
./start.sh
```

Vulkan/RADV is the default. For ROCm: `FLASH_NEXT_ROCM=1 ./start.sh`.

## Security defaults

| Knob | Default |
|---|---|
| Bind | `127.0.0.1` only |
| CORS | `localhost` (not `*`) |
| Credentials CORS | off |
| API key | required (`api-key.txt` / `FLASH_NEXT_API_KEY`) |
| Web UI | off |
| `/props` | off |
| `/metrics` and `/slots` | on, behind the API key |

The llama.cpp warning about CORS `*` is gone with these flags.

## Draft acceptance

It is **not** printed while tokens stream. After each completion, llama.cpp
logs a line like:

```
draft acceptance = 0.66 (325 accepted / 491 generated), mean len = 2.76
```

Then run:

```powershell
.\stats.ps1
```

That hits `/metrics` and `/slots` with the API key and greps the latest log.

If that line never appears, speculation is off (wrong engine, shared head
dropped, or `--spec-type` missing).

## DFlash2

**Not for this model.** DFlash2 GGUFs (`incoai/Qwen3.8-27B-DFlash2-GGUF`) are
trained for **Qwen3.8-27B**, a dense 27B with different hidden size. Flash-Next
is `qwen4exp` (125B-A6B + 51B n-gram). A mismatched DFlash2 pair is rejected
or drafts garbage.

The engine *flag* `--spec-type draft-dflash` exists. There is **no published
Flash-Next DFlash2 drafter**. Speed left on the table here is Linux RADV +
n-max tuning + ngram-mod on rewrites, not DSpark/DFlash2.

Do not stack DFlash2 and MTP.

## Expected speed (128 GB Strix Halo)

| Setup | Decode |
|---|---|
| LM Studio, no MTP | ~11 tok/s |
| This recipe, Windows Vulkan + MTP n-max 3 | **~23 tok/s** |
| Linux RADV + MTP + ngram-mod, code/rewrite | 30–47 tok/s class (community) |

n-max 3 is the default. n-max 8 is slower.

## Git

Weights and the engine are not in git (see `.gitignore`). Clone, run
`setup.ps1` / download GGUFs, copy `.env.example` → `.env`.
