//
//  RecordMappingTests.swift
//  TadaTests
//

import XCTest
import CloudKit
import CoreData
@testable import Done_done

final class RecordMappingTests: XCTestCase {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func zoneID() -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "test-zone", ownerName: CKCurrentUserDefaultName)
    }

    /// Assigning to a key CKRecord reserves throws NSInvalidArgumentException, which is an
    /// Objective-C exception Swift cannot catch — it takes the whole app down the first time the
    /// sync engine builds a batch. Building the records here is the check.
    @MainActor
    func testListRecordAvoidsReservedKeys() throws {
        let context = makeContext()
        let list = TodoList.create(name: "Groceries", order: 3, in: context)
        try context.save()

        let recordID = CKRecord.ID(recordName: list.id!.uuidString, zoneID: zoneID())
        let record = CloudKitManager.shared.makeRecord(for: list, recordID: recordID)

        XCTAssertEqual(record.recordType, CloudKitManager.RecordType.list)
        XCTAssertEqual(record["name"] as? String, "Groceries")
        XCTAssertEqual(record["order"] as? Int64, 3)

        let used = Set(record.allKeys())
        XCTAssertTrue(
            used.isDisjoint(with: CloudKitManager.reservedRecordKeys),
            "record uses keys CKRecord reserves: \(used.intersection(CloudKitManager.reservedRecordKeys))"
        )
    }

    @MainActor
    func testItemRecordAvoidsReservedKeys() throws {
        let context = makeContext()
        let list = TodoList.create(name: "Groceries", order: 0, in: context)
        let item = TodoItem.create(text: "Milk", order: 1, list: list, in: context)
        try context.save()

        let recordID = CKRecord.ID(recordName: item.id!.uuidString, zoneID: zoneID())
        let record = CloudKitManager.shared.makeRecord(for: item, recordID: recordID)

        XCTAssertEqual(record.recordType, CloudKitManager.RecordType.item)
        XCTAssertEqual(record["text"] as? String, "Milk")
        XCTAssertEqual(record["listID"] as? String, list.id!.uuidString)

        let used = Set(record.allKeys())
        XCTAssertTrue(
            used.isDisjoint(with: CloudKitManager.reservedRecordKeys),
            "record uses keys CKRecord reserves: \(used.intersection(CloudKitManager.reservedRecordKeys))"
        )
    }

    /// Pins the fields the app writes. CloudKit only creates a field once some record carries a
    /// value for it, so a field that is usually nil — completionTime, startedTime — can be absent
    /// from the schema until a user happens to set one, and then fail against production where
    /// fields are never created implicitly. If this test fails because you added a field, add it
    /// to cloudkit/schema.ckdb and deploy before testing on a device.
    @MainActor
    func testFullyPopulatedRecordsWriteTheExpectedFields() throws {
        let context = makeContext()
        let list = TodoList.create(name: "Trip", order: 0, in: context)
        let item = TodoItem.create(text: "Passport", order: 0, list: list, in: context)
        item.completionTime = Date()
        item.startedTime = Date()
        item.isHidden = true
        try context.save()

        let listRecord = CloudKitManager.shared.makeRecord(
            for: list,
            recordID: CKRecord.ID(recordName: list.id!.uuidString, zoneID: zoneID())
        )
        XCTAssertEqual(
            Set(listRecord.allKeys()),
            ["name", "order", "listCreationDate"]
        )

        let itemRecord = CloudKitManager.shared.makeRecord(
            for: item,
            recordID: CKRecord.ID(recordName: item.id!.uuidString, zoneID: zoneID())
        )
        XCTAssertEqual(
            Set(itemRecord.allKeys()),
            ["text", "order", "creationTime", "completionTime", "startedTime", "isHidden", "listID"]
        )
    }

    /// Each list must sync in its own zone, since that is what makes a list shareable on its own.
    @MainActor
    func testEachListGetsItsOwnZone() throws {
        let context = makeContext()
        let first = TodoList.create(name: "A", order: 0, in: context)
        let second = TodoList.create(name: "B", order: 1, in: context)
        try context.save()

        XCTAssertNotNil(first.zoneName)
        XCTAssertNotEqual(first.zoneName, second.zoneName)
    }
}
