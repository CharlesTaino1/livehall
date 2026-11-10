import Darwin
import Foundation

struct ProcessUsage: Sendable {
    let cpuSeconds: Double
    let memoryMegabytes: Double

    static func current() -> ProcessUsage {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = seconds(usage.ru_utime) + seconds(usage.ru_stime)

        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
            }
        }
        let footprint = status == 0 ? Double(info.ri_phys_footprint) / 1_048_576 : 0
        return ProcessUsage(cpuSeconds: cpu, memoryMegabytes: footprint)
    }

    private static func seconds(_ time: timeval) -> Double {
        Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }
}
