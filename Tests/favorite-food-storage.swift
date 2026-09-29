import Foundation
import SwiftData

@main
struct FavoriteFoodStorageTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: FavoriteFood.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let writer = ModelContext(container)
        let photo = Data([0xff, 0xd8, 0xff, 0xd9])
        writer.insert(FavoriteFood(name: "早餐牛奶", portion: "1盒 250 ml", calories: 145,
                                   protein: 8, carbs: 12, fat: 7, photoData: photo))
        try writer.save()

        let reader = ModelContext(container)
        let loaded = try reader.fetch(FetchDescriptor<FavoriteFood>()).first!
        assert(loaded.name == "早餐牛奶" && loaded.portion == "1盒 250 ml")
        assert(loaded.calories == 145 && loaded.protein == 8 && loaded.photoData == photo)
        assert(loaded.nutritionSummary.contains("145") && loaded.nutritionSummary.contains("250 ml"))
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("favorite-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appendingPathComponent("records.sqlite")
        do {
            let legacy = try ModelContainer(for: MealEntry.self, configurations: ModelConfiguration(url: database))
            let legacyContext = ModelContext(legacy)
            legacyContext.insert(MealEntry(kind: .breakfast, name: "旧餐", calories: 200, protein: 8, carbs: 25, fat: 7))
            try legacyContext.save()
        }
        do {
            let upgraded = try ModelContainer(for: MealEntry.self, FavoriteFood.self, configurations: ModelConfiguration(url: database))
            let upgradedContext = ModelContext(upgraded)
            let oldMeal = try upgradedContext.fetch(FetchDescriptor<MealEntry>()).first
            assert(oldMeal?.name == "旧餐")
            upgradedContext.insert(FavoriteFood(name: "面包", calories: 180))
            try upgradedContext.save()
            let savedFoods = try upgradedContext.fetch(FetchDescriptor<FavoriteFood>())
            assert(savedFoods.count == 1)
        }
        print("PASS: favorite food photo, nutrition and existing-store migration")
    }
}
