import Foundation

/// Writes a ride as a Garmin TCX file.
///
/// This is the export path that always works. Swift Playgrounds cannot grant the HealthKit
/// entitlement, so a shareable file is how a ride leaves the iPad — TCX imports into
/// Strava, TrainingPeaks, intervals.icu and Garmin Connect, all of which read the power
/// and cadence extensions written here.
enum TCXExporter {

    static func write(engine: RideEngine, startedAt: Date) throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" \
        xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
          <Activities>
            <Activity Sport="Biking">
              <Id>\(iso.string(from: startedAt))</Id>
              <Lap StartTime="\(iso.string(from: startedAt))">
                <TotalTimeSeconds>\(engine.samples.count)</TotalTimeSeconds>
                <DistanceMeters>0</DistanceMeters>
                <MaximumSpeed>0</MaximumSpeed>
                <Calories>0</Calories>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>

        """

        for s in engine.samples {
            let t = iso.string(from: startedAt.addingTimeInterval(Double(s.time)))
            xml += """
                      <Trackpoint>
                        <Time>\(t)</Time>
                        <Cadence>\(min(254, max(0, s.cadence)))</Cadence>
                        <Extensions>
                          <ns3:TPX>
                            <ns3:Watts>\(max(0, s.watts))</ns3:Watts>
                          </ns3:TPX>
                        </Extensions>
                      </Trackpoint>

            """
        }

        xml += """
                </Track>
              </Lap>
              <Notes>\(escape(engine.workout.title)) — \(escape(engine.workout.instructor))</Notes>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """

        let name = "PowerZone-\(fileStamp(startedAt)).tcx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: date)
    }
}
