# Setup

What a fresh clone does *not* give you, in the order it bites.

## 1. prjxray C++ tools

`bitread` and `segmatch` are needed by every fuzzer.

```bash
cd prjxray
git submodule update --init third_party/sanitizers-cmake third_party/googletest \
    third_party/gflags third_party/cctz third_party/abseil-cpp third_party/yaml-cpp
mkdir -p build && cd build && cmake .. && make -j bitread segmatch
```

`make build` at the top level would also pull `third_party/yosys`, which is
large and unnecessary — the fuzzers synthesise with Vivado.

## 2. Python environment

```bash
cd prjxray
python3 -mvenv env
./env/bin/pip install numpy pyyaml simplejson intervaltree fasm pyjson5 parse textx
./env/bin/pip install -e .
```

`requirements.txt` lists `-e third_party/fasm` and `-e third_party/python-sdf-timing`
as editable installs of submodules skipped above; `fasm` from PyPI serves
instead. Verify with:

```bash
./env/bin/python -c "from prjxray.segmaker import Segmaker"
```

## 3. Reference database

`prjxray/database/` ships nearly empty — only `settings.sh` per family. The
real database lives in a separate repo, and `segmaker` cannot run without its
`tilegrid.json`.

```bash
git clone --depth 1 https://github.com/f4pga/prjxray-db.git
```

Clone it *beside* `prjxray`, not into `prjxray/database/`. Here it is the
read-only reference that results are validated against; `env/xray_env.sh`
points `XRAY_DATABASE_DIR` at it. Never run `pushdb`/`mergedb` into it.

Layout note: `tilegrid.json` is per **device** (`artix7/xc7a100t/`) while
`part.yaml` is per **part** (`artix7/xc7a100tfgg676-1/`).

## 4. `settings/<family>/resources.yaml`

This one is easy to miss. `settings/artix7.sh` ends by running
`utils/create_environment.py`, which reads `settings/artix7/resources.yaml` to
set `XRAY_PIN_00..03`. That file is **generated and gitignored**, so a fresh
clone fails with:

```
AssertionError: Mapping file .../settings/artix7/resources.yaml does not exist
```

Generate it for every part this tree targets with:

```bash
rw-fuzzers/env/gen_resources.sh
```

That runs `utils/update_resources.tcl` under Vivado once per part — it reports
clock-capable and general-purpose package pins — and picks
`clk[0]`, `data[0]`, `data[len/2]`, `data[-1]`, exactly as
`utils/update_resources.py` does. Results are merged per family, because
prjxray's `set_part_resources()` opens the file `"w+"`: writing one part at a
time would clobber the others.

`utils/update_resources.py` itself loops over *every* part in the database
(hundreds) and needs a Linux Vivado, so it is not usable here.

Caveat: the chosen pins are whatever **Vivado 2024.2** reports as the first
clock-capable pin and the first/middle/last general-purpose pins. Vivado 2017.2
may order `get_package_pins` differently and pick different ones. It makes no
difference to the CLB bits validated so far — the LUTs do not care which pin the
clock enters on — but a future IOB or IOI fuzzer port inherits these pins, and
should have its own prjxray-db diff before the results are trusted.

Parts covered, one per prjxray settings config:

| family | parts |
| --- | --- |
| artix7 | xc7a50tfgg484-1, xc7a100tfgg676-1, xc7a200tffg1156-1 |
| kintex7 | xc7k70tfbg676-2, xc7k160tffg676-2 |
| spartan7 | xc7s50fgga484-1 |
| zynq7 | xc7z010clg400-1, xc7z020clg484-1 |

## 5. RapidWright

```bash
cd RapidWright && ./gradlew compileJava
```

The core classes (`Device`, `Design`, `Tile`, `Site`, `PIP`, `Bitstream`) are
**not** in the git tree — they arrive as the binary `rapidwright-api-lib` Maven
artifact. Nothing to do about it, but it explains why `find src -name Device.java`
comes up empty. Device data for 7-series downloads on first `Device.getDevice()`.

Record the classpath for the fuzzer scripts:

```bash
find ~/.gradle/caches/modules-2 -name '*.jar' | grep -v -- '-sources\|-javadoc' \
    | tr '\n' ':' > rw-fuzzers/env/rw_classpath.txt
# then append RapidWright/build/classes/java/main
```

## 6. Vivado on WSL

A Windows Vivado install cannot be launched through `bin/vivado` from WSL — that
is the Linux loader and it will fail looking for `unwrapped/lnx64.o`. Use
`env/vivado.sh`, which goes through `cmd.exe` and `vivado.bat`. Set
`XRAY_VIVADO_BAT` if the install is not at
`E:\Xilinx\Vivado\2024.2\bin\vivado.bat`.

Two things this must get right, both already handled in the wrapper:

* **Paths** — file arguments are translated with `wslpath -w`.
* **Environment** — Windows processes do not inherit the WSL environment, so
  `$::env(XRAY_*)` reads in prjxray's Tcl would fail. The wrapper exports
  `WSLENV`, whose `/p` flag also path-translates the vars that hold paths.
  Emitting `set VAR=...` into the `cmd.exe` command line is *not* a workable
  alternative: values like `XRAY_ROI` contain spaces and colons and the nested
  quoting is not parsed reliably.

Specimen directories must be on a Windows-visible mount (`/mnt/...`).

Note that files Vivado writes have **CRLF** line endings, which matters when
diffing its output against RapidWright's.
