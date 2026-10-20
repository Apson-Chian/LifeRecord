package ltd.apsonchian.liferecord

import android.Manifest
import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import ltd.apsonchian.liferecord.data.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class IsolationTest {
    @Test fun targetCannotShareUserPackageOrInternetPermission() {
        val app = TestIsolation.app()
        assertEquals(IsolatedLifeRecordApplication.PACKAGE, app.packageName)
        assertTrue(app.applicationInfo.dataDir.endsWith(app.packageName))
        assertEquals(PackageManager.PERMISSION_DENIED, app.checkSelfPermission(Manifest.permission.INTERNET))
        assertEquals("instrumented.db", app.store.databaseName)
    }
    @Test fun clearingFixturesPreservesIndependentSentinelStoreAndSecrets() {
        val app = TestIsolation.app()
        Store(app, "sentinel.db").use { sentinel ->
            val r = Record.create(RecordType.BODY)
            sentinel.commit(Snapshot(listOf(r), defaultProfile(), emptyList()))
            val sentinelSecrets = Secrets(app, "sentinel-secrets", "liferecord.sentinel")
            sentinelSecrets.save("sentinel", "synthetic-only")
            try {
                val interrupted = runCatching {
                    app.store.clearAll(); app.secrets.save("sync", "fake-only"); app.secrets.clear()
                    throw java.util.concurrent.CancellationException("Injected fixture interruption")
                }
                assertTrue(interrupted.exceptionOrNull() is java.util.concurrent.CancellationException)
                assertEquals(r.id, sentinel.load().records.single().id)
                assertEquals("synthetic-only", sentinelSecrets.get("sentinel"))
            } finally { sentinelSecrets.clear() }
        }
        app.deleteDatabase("sentinel.db")
    }
    @Test fun syncUsesFakeAndProductionOverrideIsRejectedBeforeAnySocket() {
        val app = TestIsolation.app()
        val r = Record.create(RecordType.BODY)
        val snapshot = Snapshot(listOf(r), defaultProfile(), emptyList())
        app.store.set("sync.base", IsolatedLifeRecordApplication.BASE)
        val result = app.network.sync(snapshot, "fake-only")
        assertEquals(r.id, result.getJSONArray("bodyMetrics").getJSONObject(0).getString("id"))
        val before = app.transport.rejected.get()
        try {
            app.store.set("sync.base", "https://apsonchian.ltd/liferecord-api")
            assertThrows(java.io.IOException::class.java) { app.network.sync(snapshot, "fake-only") }
            assertEquals(before + 1, app.transport.rejected.get())
        } finally { app.store.set("sync.base", IsolatedLifeRecordApplication.BASE) }
    }
}
