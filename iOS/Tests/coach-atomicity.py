"""Compile the actual private CoachView writer with isolated collaborators.
The generated bridge only replaces the commit call to inject disk-full, and routes
standard defaults to a dedicated suite. No UI or network implementation is used.
"""
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[2]
source=Path(os.environ.get('LIFERECORD_COACH_TEST_SOURCE',root/'iOS/LifeRecord/Views/CoachView.swift')).read_text()
start=source.index('    @MainActor\n    private struct ActionExecution')
end=source.index('    /// Explicit times',start)
writer=source[start:end].replace('UserDefaults.standard','testDefaults')
writer=writer.replace('try modelContext.save()','try injectedSave(modelContext)')
writer=writer.replace('try persist(modelContext)','try injectedSave(modelContext)')
# Both the old and the new writer run their real control flow; only I/O endpoints
# and one deterministic failure point are injected.
extra_defaults = ',preferenceDefaults:testDefaults' if 'preferenceDefaults: UserDefaults' in writer else ''
bridge='''import Foundation
import SwiftData
@MainActor final class CoachWriterProbe {
    let modelContext: ModelContext
    let settings: AppSettings
    let syncCoordinator = SyncCoordinator()
    let testDefaults: UserDefaults
    var shouldFail = true
    var meals: [MealEntry] { try! modelContext.fetch(FetchDescriptor<MealEntry>()) }
    var bodyMetrics: [BodyMetric] { try! modelContext.fetch(FetchDescriptor<BodyMetric>()) }
    var workouts: [WorkoutEntry] { try! modelContext.fetch(FetchDescriptor<WorkoutEntry>()) }
    init(context: ModelContext, settings: AppSettings, defaults: UserDefaults) { modelContext=context; self.settings=settings; testDefaults=defaults }
    func injectedSave(_ context:ModelContext) throws { if shouldFail { throw NSError(domain:"InjectedDiskFull",code:28) }; try context.save() }
    func run(_ actions:[AIAgentAction]) async throws { _ = try await apply(actions,attachedImages:[],inputText:"synthetic",conversationID:UUID(),explicitlyRequestedDate:nil) }
'''+writer+'\n}\n'
bridge=bridge.replace('explicitlyRequestedDate:nil)', 'explicitlyRequestedDate:nil'+extra_defaults+')')
with tempfile.TemporaryDirectory(prefix='liferecord-coach-atomic-') as folder:
    directory=Path(folder); (directory/'Writer.swift').write_text(bridge)
    sources=['Services/WorkoutDetails.swift','Models/HealthModels.swift','Services/AppSettings.swift','Services/RecordInput.swift','Services/AIAuthentication.swift','Services/CoachActions.swift']
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(directory/'cache'),*[str(root/'iOS/LifeRecord'/s) for s in sources],str(directory/'Writer.swift'),str(root/'iOS/Tests/coach-atomicity.swift'),'-o',str(directory/'check')],check=True)
    subprocess.run([str(directory/'check')],check=True)
