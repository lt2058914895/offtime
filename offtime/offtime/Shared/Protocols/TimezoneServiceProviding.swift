import Foundation

protocol TimezoneServiceProviding: AnyObject {
    func getLocalTime24(timezoneId: String, date: Date) -> String?
    func getLocalTime12(timezoneId: String, date: Date) -> String?
    func getLocalDate(timezoneId: String, date: Date) -> String?
    func getLocalWeekday(timezoneId: String, date: Date) -> String?
    func getLocalDateTime(timezoneId: String, date: Date) -> String?
    func getLocalizedTime(timezoneId: String, date: Date) -> String?
    func getMonthDay(timezoneId: String, date: Date) -> String?
    func getUTCText(timezoneId: String) -> String?
    func isDaytime(timezoneId: String, date: Date) -> Bool
    func getTimeDifference(timezoneId: String, date: Date) -> (offset: String, crossDay: String?)
    func getTimeDifferenceBetween(sourceTimezoneId: String, targetTimezoneId: String, date: Date) -> (offset: String, crossDay: String?)
    func convertTime(sourceTimezoneId: String, targetTimezoneId: String, sourceDate: Date) -> Date?
    func getTimezoneInfo(timezoneId: String) -> TimezoneInfo?
    func getDSTStatus(timezoneId: String, date: Date) -> String?
    func getWorkingHoursOverlap(
        timezoneId: String,
        date: Date,
        localTimezoneId: String,
        localWorkStart: Int,
        localWorkEnd: Int,
        targetWorkStart: Int,
        targetWorkEnd: Int
    ) -> WorkingHoursOverlap
}

extension TimezoneService: TimezoneServiceProviding {}
