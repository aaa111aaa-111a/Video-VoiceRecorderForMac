import CoreMedia

/// The clock both capture paths timestamp against. Wrapped so tests can reason about it
/// and so there is exactly one place that decides what "now" means for the mix timeline.
enum HostClock {
    static func now() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }
}
