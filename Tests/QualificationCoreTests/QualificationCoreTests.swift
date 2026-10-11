import XCTest
import QualificationCore
final class QualificationCoreTests:XCTestCase {
    func testSeededBoundedScheduleCoversEverySchemaAndScenario() {
        var a=QualificationSchedule(),b=QualificationSchedule();var pairs=Set<String>()
        for _ in 0..<8192 {let x=a.next(),y=b.next();XCTAssertEqual(x.schema,y.schema);XCTAssertEqual(x.scenario,y.scenario);pairs.insert("\(x.schema):\(x.scenario)")}
        XCTAssertEqual(pairs.count,256);XCTAssertEqual(a.episode,8192)
        XCTAssertEqual(QualificationSchedule.minimumEvents,1_000_000);XCTAssertEqual(QualificationSchedule.calibrationEvents,10_000)
    }
    func testRecordHasFourLittleEndianWordsWithoutInputContent() {
        let data=QualificationTimingRecord(operation:2,owner:0x0102030405060708,nativeAction:9,contextCopy:10).data
        XCTAssertEqual(data.count,32);XCTAssertEqual(Array(data[8..<16]),[8,7,6,5,4,3,2,1]);XCTAssertEqual(data[0],2);XCTAssertEqual(data[16],9);XCTAssertEqual(data[24],10)
    }
}
