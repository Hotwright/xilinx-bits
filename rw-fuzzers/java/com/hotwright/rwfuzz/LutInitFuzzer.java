package com.hotwright.rwfuzz;

import java.io.IOException;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import com.xilinx.rapidwright.design.Cell;
import com.xilinx.rapidwright.design.Design;

/**
 * RapidWright replacement for the design-mutation half of prjxray's
 * fuzzers/010-clb-lutinit/generate.tcl.
 *
 * The Tcl does four things: build/place/route a design, permute every LUT6
 * INIT, write a bitstream per permutation, and dump a "LOC BEL INIT" text file
 * per permutation for segmaker. Only bitstream generation actually requires
 * Vivado. This tool takes a placed-and-routed base checkpoint and emits one
 * checkpoint plus one tag file per variant; the caller then runs Vivado with
 * nothing more than "open_checkpoint; write_bitstream".
 *
 * Cell iteration order deliberately does not try to match Vivado's
 * "get_cells -hierarchical" order. The tag file records the INIT actually
 * applied to each cell, so segmaker correlates against ground truth regardless
 * of which pattern a given LUT received.
 */
public class LutInitFuzzer {

    /** Same patterns, and same meaning, as generate.tcl's pattern_list. */
    private static final long[] PATTERNS = {
        0x1234567812345678L,
        0xFFFFFFFF00000000L,
        0xFFFF0000FFFF0000L,
        0xFF00FF00FF00FF00L,
        0xF0F0F0F0F0F0F0F0L,
        0xCCCCCCCCCCCCCCCCL,
        0xAAAAAAAAAAAAAAAAL,
    };

    private static final String INIT = "INIT";

    public static void main(String[] args) throws IOException {
        if (args.length < 2) {
            System.err.println(
                "usage: LutInitFuzzer <base.dcp> <outDir> [variants] [base.edf]\n"
                + "  variants: comma-separated list (default 0,1,2)\n"
                + "            0 = unmodified, 1 = XOR patterns, 2 = set patterns,\n"
                + "            >=3 = pseudo-random INITs seeded by the variant number\n"
                + "  base.edf: readable EDIF exported next to the checkpoint.\n"
                + "            Vivado embeds encrypted EDIF in a DCP, which\n"
                + "            RapidWright can only read by calling Vivado itself.");
            System.exit(1);
        }
        Path baseDcp = Paths.get(args[0]);
        Path outDir = Paths.get(args[1]);
        Files.createDirectories(outDir);

        String variantSpec = args.length > 2 ? args[2] : "0,1,2";
        // Default to design.edf beside the checkpoint when present.
        Path baseEdf = args.length > 3 ? Paths.get(args[3])
            : siblingEdf(baseDcp);

        for (String v : variantSpec.split(",")) {
            int variant = Integer.parseInt(v.trim());
            // Re-read the checkpoint per variant: mutations are applied to the
            // in-memory netlist, so each variant must start from the base.
            Design design = (baseEdf != null)
                ? Design.readCheckpoint(baseDcp, baseEdf)
                : Design.readCheckpoint(baseDcp);
            List<Cell> luts = lut6Cells(design);
            if (luts.isEmpty()) {
                throw new IllegalStateException("no placed LUT6 cells in " + baseDcp);
            }
            applyVariant(luts, variant);

            Path dcp = outDir.resolve("design_" + variant + ".dcp");
            Path txt = outDir.resolve("design_" + variant + ".txt");
            design.writeCheckpoint(dcp);
            writeTagFile(luts, txt);
            System.out.printf("variant %d: %d LUT6 cells -> %s, %s%n",
                variant, luts.size(), dcp.getFileName(), txt.getFileName());
        }
    }

    /** design.dcp -> design.edf, if that file exists. */
    private static Path siblingEdf(Path dcp) {
        String name = dcp.getFileName().toString().replaceFirst("\\.dcp$", ".edf");
        Path edf = dcp.resolveSibling(name);
        return Files.exists(edf) ? edf : null;
    }

    /**
     * Placed LUT6 cells, in a deterministic order so that repeated runs of the
     * same variant produce identical output.
     */
    private static List<Cell> lut6Cells(Design design) {
        List<Cell> luts = new ArrayList<>();
        for (Cell c : design.getCells()) {
            if (!"LUT6".equals(c.getType())) continue;
            // Unplaced cells have no site/BEL and cannot be tagged.
            if (c.getSiteName() == null || c.getBELName() == null) continue;
            luts.add(c);
        }
        luts.sort(Comparator.comparing(Cell::getSiteName).thenComparing(Cell::getBELName));
        return luts;
    }

    private static void applyVariant(List<Cell> luts, int variant) {
        if (variant == 0) return;                 // unmodified reference
        if (variant >= 3) {                       // see randomInit()
            for (Cell c : luts) {
                c.addProperty(INIT, formatInit(randomInit(variant, c)));
            }
            return;
        }
        // generate.tcl starts the XOR pass at pattern 0 and the set pass at 1.
        int patternIndex = (variant == 1) ? 0 : 1;
        for (Cell c : luts) {
            long value;
            if (variant == 1) {
                value = parseInit(c.getPropertyValueString(INIT)) ^ PATTERNS[patternIndex];
            } else {
                value = PATTERNS[patternIndex];
            }
            c.addProperty(INIT, formatInit(value));
            patternIndex = (patternIndex + 1) % PATTERNS.length;
        }
    }

    /** Accepts "64'hABCD...", "0xABCD..." or bare hex; returns the 64-bit value. */
    /**
     * A per-cell pseudo-random INIT.
     *
     * The three variants ported from generate.tcl leave segmatch slightly
     * under-constrained: a few tags come back with two candidate bits because
     * some unrelated bit happens to track the tag across only three
     * permutations. Upstream answers that with more specimens, i.e. more full
     * synth/place/route runs. Here extra permutations of the existing base
     * checkpoint are nearly free - RapidWright rewrites the netlist in well
     * under a second - so more variants are the cheaper way to break the tie.
     *
     * Deterministic in (variant, site, bel), so runs stay reproducible.
     */
    static long randomInit(int variant, Cell c) {
        long h = 0xcbf29ce484222325L;             // FNV-1a, 64 bit
        for (byte b : (variant + ":" + c.getSiteName() + "/" + c.getBELName()).getBytes()) {
            h = (h ^ (b & 0xff)) * 0x100000001b3L;
        }
        // FNV alone leaves low-order structure; SplitMix64 finalizer clears it.
        h ^= h >>> 30; h *= 0xbf58476d1ce4e5b9L;
        h ^= h >>> 27; h *= 0x94d049bb133111ebL;
        return h ^ (h >>> 31);
    }

    static long parseInit(String raw) {
        if (raw == null) throw new IllegalArgumentException("cell has no INIT property");
        String s = raw.trim();
        int h = s.indexOf('h');
        if (h >= 0) {
            s = s.substring(h + 1);
        } else if (s.startsWith("0x") || s.startsWith("0X")) {
            s = s.substring(2);
        }
        return Long.parseUnsignedLong(s, 16);
    }

    static String formatInit(long value) {
        return String.format("64'h%016X", value);
    }

    /**
     * The "LOC BEL INIT" format read by 010-clb-lutinit/generate.py, which
     * strips the leading "64'h" from the third field.
     */
    private static void writeTagFile(List<Cell> luts, Path txt) throws IOException {
        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(txt))) {
            for (Cell c : luts) {
                w.printf("%s %s %s%n",
                    c.getSiteName(),
                    c.getBELName(),
                    formatInit(parseInit(c.getPropertyValueString(INIT))));
            }
        }
    }
}
