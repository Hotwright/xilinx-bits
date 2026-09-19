package com.hotwright.rwfuzz;

import com.xilinx.rapidwright.device.Device;
import com.xilinx.rapidwright.device.Site;
import com.xilinx.rapidwright.device.SiteTypeEnum;
import com.xilinx.rapidwright.device.Tile;

import java.util.Map;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Dump the geometry prjxray's settings/&lt;config&gt;.sh needs for a part, without
 * Vivado.
 *
 * 005-tilegrid wants XRAY_ROI_TILEGRID as site ranges (SLICE_X0Y0:SLICE_XnYm
 * and the same for RAMB18/RAMB36/DSP48) and XRAY_ROI_GRID_* as tile column and
 * row bounds. Both are static device facts, so RapidWright's offline device
 * model answers them and leaves Vivado free for the fuzzer itself.
 *
 * Also prints the tile-type and site-type inventory, because 005's Makefile
 * builds its sub-fuzzers unconditionally: a device without XADC (monitor),
 * MMCM or PLL sites fails the whole `database` target partway through, and it
 * is much cheaper to find that out here.
 *
 * usage: DeviceExtents <part>
 */
public class DeviceExtents {

    /** SLICE_X12Y34 -> the 12 and the 34. */
    private static final Pattern SITE_XY = Pattern.compile("^(.*?)_X(\\d+)Y(\\d+)$");

    private static class Extent {
        int minX = Integer.MAX_VALUE, maxX = Integer.MIN_VALUE;
        int minY = Integer.MAX_VALUE, maxY = Integer.MIN_VALUE;

        void add(int x, int y) {
            minX = Math.min(minX, x);
            maxX = Math.max(maxX, x);
            minY = Math.min(minY, y);
            maxY = Math.max(maxY, y);
        }
    }

    public static void main(String[] args) {
        if (args.length != 1) {
            System.err.println("usage: DeviceExtents <part>");
            System.exit(2);
        }
        Device device = Device.getDevice(args[0]);
        if (device == null) {
            System.err.println("no device data for " + args[0]);
            System.exit(1);
        }

        // Site prefixes are grouped by name rather than SiteTypeEnum because
        // that is the spelling XRAY_ROI_TILEGRID uses: SLICEL and SLICEM sites
        // are both named SLICE_*, and prjxray ranges them as one series.
        Map<String, Extent> byPrefix = new TreeMap<>();
        Map<SiteTypeEnum, Integer> siteTypeCounts = new TreeMap<>();

        for (Tile tile : device.getAllTiles()) {
            for (Site site : tile.getSites()) {
                siteTypeCounts.merge(site.getSiteTypeEnum(), 1, Integer::sum);
                Matcher m = SITE_XY.matcher(site.getName());
                if (!m.matches()) continue;
                byPrefix.computeIfAbsent(m.group(1), k -> new Extent())
                        .add(Integer.parseInt(m.group(2)), Integer.parseInt(m.group(3)));
            }
        }

        System.out.println("# part: " + args[0] + "  device: " + device.getName());
        System.out.println("# tile grid: " + device.getColumns() + " columns x "
                + device.getRows() + " rows");

        System.out.println();
        System.out.println("## site ranges (XRAY_ROI_TILEGRID candidates)");
        for (String prefix : new String[] {"SLICE", "RAMB18", "RAMB36", "DSP48"}) {
            Extent e = byPrefix.get(prefix);
            if (e == null) {
                System.out.printf("%-8s ABSENT%n", prefix);
                continue;
            }
            System.out.printf("%-8s %s_X%dY%d:%s_X%dY%d%n", prefix,
                    prefix, e.minX, e.minY, prefix, e.maxX, e.maxY);
        }

        // XRAY_ROI_TILEGRID is a list of ranges, not a bounding box, and the
        // difference matters: xc7s50's own settings file splits RAMB18 into
        // "X0Y0:X1Y59" plus "X2Y0:X2Y39" because its third BRAM column is
        // shorter than the other two. A bounding box would silently claim
        // sites that do not exist.
        System.out.println();
        System.out.println("## per-column Y extents (XRAY_ROI_TILEGRID must respect these)");
        for (String prefix : new String[] {"SLICE", "RAMB18", "RAMB36", "DSP48"}) {
            Map<Integer, Extent> cols = new TreeMap<>();
            for (Tile tile : device.getAllTiles()) {
                for (Site site : tile.getSites()) {
                    Matcher m = SITE_XY.matcher(site.getName());
                    if (!m.matches() || !m.group(1).equals(prefix)) continue;
                    int x = Integer.parseInt(m.group(2));
                    int y = Integer.parseInt(m.group(3));
                    cols.computeIfAbsent(x, k -> new Extent()).add(x, y);
                }
            }
            if (cols.isEmpty()) continue;
            // Collapse adjacent columns that share a Y range into one range,
            // which is the spelling the settings files use.
            StringBuilder ranges = new StringBuilder();
            Integer runStart = null;
            Extent runExtent = null;
            for (Map.Entry<Integer, Extent> en : cols.entrySet()) {
                Extent e = en.getValue();
                if (runExtent != null && e.minY == runExtent.minY && e.maxY == runExtent.maxY
                        && en.getKey() == runExtent.maxX + 1) {
                    runExtent.add(en.getKey(), e.minY);
                    continue;
                }
                if (runExtent != null) {
                    ranges.append(String.format("%s_X%dY%d:%s_X%dY%d ", prefix, runStart,
                            runExtent.minY, prefix, runExtent.maxX, runExtent.maxY));
                }
                runStart = en.getKey();
                runExtent = new Extent();
                runExtent.add(en.getKey(), e.minY);
                runExtent.add(en.getKey(), e.maxY);
            }
            ranges.append(String.format("%s_X%dY%d:%s_X%dY%d", prefix, runStart,
                    runExtent.minY, prefix, runExtent.maxX, runExtent.maxY));
            System.out.printf("%-8s %s%n", prefix, ranges.toString());
            for (Map.Entry<Integer, Extent> en : cols.entrySet()) {
                System.out.printf("           X%-3d Y%d..%d%n", en.getKey(),
                        en.getValue().minY, en.getValue().maxY);
            }
        }

        System.out.println();
        System.out.println("## all site name prefixes");
        for (Map.Entry<String, Extent> en : byPrefix.entrySet()) {
            Extent e = en.getValue();
            System.out.printf("%-24s X%d..%d Y%d..%d%n", en.getKey(),
                    e.minX, e.maxX, e.minY, e.maxY);
        }

        System.out.println();
        System.out.println("## site types present (005 sub-fuzzer preconditions)");
        for (Map.Entry<SiteTypeEnum, Integer> en : siteTypeCounts.entrySet()) {
            System.out.printf("%-24s %d%n", en.getKey(), en.getValue());
        }

        System.out.println();
        System.out.println("## tile types present");
        TreeSet<String> tileTypes = new TreeSet<>();
        for (Tile tile : device.getAllTiles()) {
            tileTypes.add(tile.getTileTypeEnum().name());
        }
        for (String t : tileTypes) {
            System.out.println(t);
        }

        // XRAY_IOI3_TILES names one specific LIOI3/RIOI3 tile per side; print
        // the candidates with their grid position so the choice can be made
        // against what generate_full.py actually does with them.
        System.out.println();
        System.out.println("## IOI3 tiles (XRAY_IOI3_TILES candidates)");
        for (Tile tile : device.getAllTiles()) {
            String tt = tile.getTileTypeEnum().name();
            if (tt.equals("LIOI3") || tt.equals("RIOI3")) {
                System.out.printf("%-24s col=%d row=%d%n", tile.getName(),
                        tile.getColumn(), tile.getRow());
            }
        }
    }
}
