import Foundation

/// Pulls the workout library out of the listing page.
///
/// The whole library — about 1,500 classes — arrives as one ~530 KB page of uppercase
/// `<TR><TD>` rows with no pagination and no API behind it. The columns are positional:
///
///   0  (empty)            6  length in minutes    12-19 per-zone seconds
///   1  full title         7  TSS                  20    class id
///   2  date mm/dd/yy      8  class type name      21    24h time
///   3  time h:mmAM ET     9  class type code      22    base class type
///   4  instructor        10  zones present
///   5  instructor first  11  air date yyyy-mm-dd
///
/// Rows that don't carry a numeric id in column 20 are headers or spacers and are skipped.
enum CatalogParser {

    static func parse(html: String) -> [CatalogEntry] {
        var entries: [CatalogEntry] = []
        var seen = Set<Int>()

        for row in WorkoutParser.matches(in: html, pattern: #"<TR>(.*?)</TR>"#) {
            guard row.count >= 2 else { continue }
            let cells = WorkoutParser.matches(in: row[1], pattern: #"<TD>(.*?)</TD>"#)
                .compactMap { $0.count >= 2 ? decode($0[1]) : nil }

            guard cells.count >= 21,
                  let id = Int(cells[20].trimmingCharacters(in: .whitespaces)),
                  !seen.contains(id)
            else { continue }
            seen.insert(id)

            entries.append(CatalogEntry(
                id: id,
                title: cells[1],
                airDate: cells[11],
                instructor: cells[4],
                minutes: Int(cells[6]) ?? 0,
                tss: Int(cells[7]) ?? 0,
                typeName: cells[8],
                typeCode: cells[9],
                zones: cells[10]
            ))
        }
        return entries
    }

    /// Instructor and class names carry the usual HTML entities ("Bike Bootcamp &amp; Co").
    private static func decode(_ s: String) -> String {
        var out = s
        for (entity, char) in [("&amp;", "&"), ("&#039;", "'"), ("&apos;", "'"),
                               ("&quot;", "\""), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
